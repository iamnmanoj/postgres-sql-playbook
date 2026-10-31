-- Payments, refunds, shipments, shipment tracking events, returns.

-- Failed attempts first (8% of orders + half the cancelled ones)
INSERT INTO sales.payments (order_id, method, status, amount, provider_ref, gateway_response, created_at)
SELECT o.order_id,
       (ARRAY['card','upi','netbanking'])[1 + (o.order_id % 3)::int]::sales.payment_method,
       'failed',
       o.grand_total,
       'pay_' || substr(md5(o.order_id || 'failed'), 1, 14),
       jsonb_build_object('gateway', (ARRAY['razorpay','stripe','payu'])[1 + (o.order_id % 3)::int],
                          'error_code', (ARRAY['INSUFFICIENT_FUNDS','CARD_DECLINED','TIMEOUT','OTP_FAILED'])[1 + (o.order_id % 4)::int],
                          'retryable', o.order_id % 4 IN (2, 3)),
       o.placed_at
FROM sales.orders o
WHERE o.order_id % 13 = 0 OR (o.status = 'cancelled' AND o.order_id % 2 = 0);

-- The successful (or still-initiated) payment for every non-cancelled order
INSERT INTO sales.payments (order_id, method, status, amount, provider_ref, gateway_response, created_at, captured_at)
SELECT o.order_id, m.method,
       (CASE o.status WHEN 'pending' THEN 'initiated' WHEN 'refunded' THEN 'refunded' ELSE 'captured' END)::sales.payment_status,
       o.grand_total,
       CASE WHEN m.method <> 'cod' THEN 'pay_' || substr(md5(o.order_id || 'ok'), 1, 14) END,
       CASE m.method
         WHEN 'card' THEN jsonb_build_object('gateway', 'razorpay',
                            'card', jsonb_build_object('network', (ARRAY['visa','mastercard','rupay','amex'])[1 + (o.order_id % 4)::int],
                                                       'last4', lpad((o.order_id * 31 % 10000)::text, 4, '0')),
                            'emi', o.grand_total > 20000 AND o.order_id % 2 = 0)
         WHEN 'upi'  THEN jsonb_build_object('gateway', 'razorpay', 'vpa', 'user' || o.user_id || '@ok' || (ARRAY['axis','hdfc','sbi','icici'])[1 + (o.order_id % 4)::int])
         WHEN 'wallet' THEN jsonb_build_object('gateway', 'payu', 'wallet', (ARRAY['paytm','phonepe','mobikwik'])[1 + (o.order_id % 3)::int])
         WHEN 'netbanking' THEN jsonb_build_object('gateway', 'payu', 'bank', (ARRAY['HDFC','SBI','ICICI','AXIS'])[1 + (o.order_id % 4)::int])
       END,
       o.placed_at + interval '2 minutes',
       CASE WHEN o.status = 'pending' THEN NULL
            WHEN m.method = 'cod' THEN least(now(), o.placed_at + interval '4 days')
            ELSE o.placed_at + interval '3 minutes' END
FROM sales.orders o
CROSS JOIN LATERAL (
    SELECT (CASE WHEN r < 0.35 THEN 'card' WHEN r < 0.75 THEN 'upi' WHEN r < 0.83 THEN 'wallet'
                 WHEN r < 0.88 THEN 'netbanking' ELSE 'cod' END)::sales.payment_method AS method
    FROM (SELECT ((o.order_id * 2654435761) % 1000) / 1000.0 AS r) x
) m
WHERE o.status <> 'cancelled';

-- Full refunds for refunded orders
INSERT INTO sales.refunds (payment_id, amount, reason, created_at, processed_at)
SELECT p.payment_id, p.amount,
       (ARRAY['customer_request','item_out_of_stock','delivery_failed'])[1 + (p.order_id % 3)::int],
       least(now(), p.created_at + interval '6 days'),
       CASE WHEN p.order_id % 10 <> 0 THEN least(now(), p.created_at + interval '8 days') END
FROM sales.payments p
WHERE p.status = 'refunded' AND p.amount > 0;

-- One shipment per order that reached the warehouse
INSERT INTO logistics.shipments (order_id, warehouse_id, carrier, tracking_number, status, shipped_at, estimated_delivery, delivered_at)
SELECT s.order_id, s.warehouse_id, s.carrier,
       upper(left(s.carrier, 3)) || lpad(s.order_id::text, 9, '0'),
       s.ship_status, s.shipped_at,
       (coalesce(s.shipped_at, s.placed_at) + interval '4 days')::date,
       CASE WHEN s.ship_status IN ('delivered', 'returned') THEN least(now(), s.shipped_at + s.transit) END
FROM (
    SELECT o.order_id, o.placed_at,
           (1 + o.order_id % 8)::smallint AS warehouse_id,
           (ARRAY['BlueDart','Delhivery','Ekart','DTDC','XpressBees'])[1 + (o.order_id % 5)::int] AS carrier,
           (CASE o.status
              WHEN 'packed'    THEN 'label_created'
              WHEN 'shipped'   THEN CASE WHEN o.order_id % 3 = 0 THEN 'out_for_delivery' ELSE 'in_transit' END
              WHEN 'delivered' THEN 'delivered'
              WHEN 'refunded'  THEN CASE WHEN o.order_id % 7 = 0 THEN 'lost' ELSE 'returned' END
            END)::logistics.shipment_status AS ship_status,
           CASE WHEN o.status <> 'packed' THEN least(now(), o.placed_at + interval '6 hours' + random() * interval '42 hours') END AS shipped_at,
           interval '1 day' + random() * interval '6 days' AS transit
    FROM sales.orders o
    WHERE o.status IN ('packed', 'shipped', 'delivered', 'refunded')
) s;

-- Tracking events: replay the journey up to the shipment's current status
INSERT INTO logistics.shipment_events (shipment_id, status, location, details, occurred_at)
SELECT s.shipment_id, e.status, e.location,
       CASE WHEN e.status = 'in_transit' THEN jsonb_build_object('hub', w.code, 'vehicle', 'KA-' || (s.shipment_id % 99))
            WHEN e.status = 'delivered' THEN jsonb_build_object('received_by', (ARRAY['customer','family member','security guard'])[1 + (s.shipment_id % 3)::int])
            ELSE '{}'::jsonb END,
       e.occurred_at
FROM logistics.shipments s
JOIN logistics.warehouses w USING (warehouse_id)
CROSS JOIN LATERAL (VALUES
    (1, 'label_created'::logistics.shipment_status, w.city, coalesce(s.shipped_at - interval '3 hours', now() - interval '1 hour')),
    (2, 'in_transit',       w.city || ' Sort Centre', s.shipped_at),
    (3, 'out_for_delivery', 'Local Delivery Hub',    greatest(s.shipped_at, coalesce(s.delivered_at, now()) - interval '5 hours')),
    (4, 'delivered',        'Customer Address',      s.delivered_at),
    (5, 'returned',         w.city,                  least(now(), s.delivered_at + interval '6 days')),
    (6, 'lost',             NULL,                    s.shipped_at + interval '10 days')
) AS e(step, status, location, occurred_at)
WHERE e.step <= CASE s.status WHEN 'label_created' THEN 1 WHEN 'in_transit' THEN 2 WHEN 'out_for_delivery' THEN 3
                              WHEN 'delivered' THEN 4 WHEN 'returned' THEN 5 ELSE 2 END
   OR (s.status = 'lost' AND e.step = 6);

-- ~4% of delivered items get a return request
INSERT INTO sales.returns (order_item_id, reason, status, requested_at, resolved_at)
SELECT r.order_item_id, r.reason, r.status, r.requested_at,
       CASE WHEN r.status <> 'requested' THEN least(now(), r.requested_at + interval '3 days') END
FROM (
    SELECT oi.order_item_id,
           (ARRAY['damaged','wrong_item','size_issue','not_as_described','changed_mind'])[1 + (oi.order_item_id % 5)::int] AS reason,
           (ARRAY['requested','approved','rejected','received','refunded','refunded','refunded'])[1 + (oi.order_item_id % 7)::int] AS status,
           least(now(), s.delivered_at + random() * interval '7 days') AS requested_at
    FROM sales.order_items oi
    JOIN sales.orders o ON o.order_id = oi.order_id AND o.status = 'delivered'
    JOIN logistics.shipments s ON s.order_id = o.order_id
    WHERE oi.order_item_id % 25 = 0
) r;

-- Partial refunds for refunded returns, linked back with a data-modifying CTE
WITH to_refund AS (
    SELECT ret.return_id, p.payment_id, oi.line_total, ret.resolved_at
    FROM sales.returns ret
    JOIN sales.order_items oi ON oi.order_item_id = ret.order_item_id
    JOIN sales.payments p ON p.order_id = oi.order_id AND p.status = 'captured'
    WHERE ret.status = 'refunded' AND oi.line_total > 0
), ins AS (
    INSERT INTO sales.refunds (payment_id, amount, reason, created_at, processed_at)
    SELECT payment_id, line_total, 'return:' || return_id, resolved_at, least(now(), resolved_at + interval '2 days')
    FROM to_refund
    RETURNING refund_id, reason
)
UPDATE sales.returns ret
SET refund_id = ins.refund_id
FROM ins
WHERE ins.reason = 'return:' || ret.return_id;
