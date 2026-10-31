-- Coupons, orders, order items, coupon redemptions, order status history.

-- Hand-made coupons (relative to today so they stay realistic whenever you build)
INSERT INTO sales.coupons (code, description, discount_type, discount_value, max_discount, min_order_amount,
                           valid_during, usage_limit, per_user_limit, seller_id, is_active)
VALUES
 ('WELCOME10', '10% off for everyone, capped at 200', 'percent', 10, 200, 0,
     tstzrange(now() - interval '800 days', now() + interval '365 days'), NULL, 1, NULL, true),
 ('FLAT100', 'Flat 100 off above 999', 'fixed', 100, NULL, 999,
     tstzrange(now() - interval '700 days', now() - interval '400 days'), 5000, 3, NULL, true),
 ('SAVE20', '20% off above 1499, max 500', 'percent', 20, 500, 1499,
     tstzrange(now() - interval '500 days', now() - interval '200 days'), 3000, 2, NULL, true),
 ('FESTIVE25', 'Festive sale: 25% off above 1999', 'percent', 25, 1000, 1999,
     tstzrange(now() - interval '390 days', now() - interval '370 days'), NULL, 1, NULL, true),
 ('PRIME15', 'Prime members: 15% off', 'percent', 15, 750, 499,
     tstzrange(now() - interval '300 days', now() + interval '60 days'), NULL, 5, NULL, true),
 ('NEWYEAR30', 'Upcoming New Year sale', 'percent', 30, 1500, 2999,
     tstzrange(now() + interval '60 days', now() + interval '70 days'), 1000, 1, NULL, true),
 ('OLDCODE', 'Retired coupon', 'fixed', 50, NULL, 0,
     tstzrange(now() - interval '900 days', NULL), NULL, 1, NULL, false);   -- open-ended range

-- One coupon per month for the last 18 months, e.g. MONTHLYJAN25
INSERT INTO sales.coupons (code, description, discount_type, discount_value, max_discount, min_order_amount, valid_during, usage_limit)
SELECT 'MONTHLY' || to_char(m, 'MONYY'),
       'Monthly deal for ' || to_char(m, 'FMMonth YYYY'),
       'percent', 5 + (extract(month FROM m)::int % 3) * 5, 300, 699,
       tstzrange(m, m + interval '1 month'),
       2000
FROM generate_series(date_trunc('month', now() - interval '17 months'), date_trunc('month', now()), interval '1 month') AS m;

-- Seller-specific coupons
INSERT INTO sales.coupons (code, description, discount_type, discount_value, min_order_amount, valid_during, seller_id)
SELECT 'STORE' || s.seller_id || 'FLAT150', 'Flat 150 off at ' || s.store_name, 'fixed', 150, 1299,
       tstzrange(now() - interval '120 days', now() + interval '120 days'), s.seller_id
FROM core.sellers s
WHERE s.seller_id <= 5;

-- 30,000 orders. Buyers are skewed (power(random(), 1.3)) -> some loyal heavy buyers.
CREATE TEMP TABLE seed_orders AS
SELECT x.g, u.user_id,
       u.created_at + random() * (now() - u.created_at) AS placed_at,
       random() AS r_status,
       random() AS r_channel
FROM (SELECT g, 1 + floor(5000 * power(random(), 1.3))::bigint AS user_id
      FROM generate_series(1, 30000) AS g) x
JOIN core.users u USING (user_id);

INSERT INTO sales.orders (order_number, user_id, shipping_address_id, status, metadata, notes, placed_at, updated_at)
SELECT 'SS-' || to_char(so.placed_at, 'YYYYMMDD') || '-' || lpad(row_number() OVER (ORDER BY so.placed_at)::text, 6, '0'),
       so.user_id,
       a.address_id,
       (CASE
          WHEN now() - so.placed_at < interval '1 day'  THEN CASE WHEN so.r_status < 0.3 THEN 'pending' ELSE 'paid' END
          WHEN now() - so.placed_at < interval '3 days' THEN CASE WHEN so.r_status < 0.5 THEN 'packed' ELSE 'shipped' END
          WHEN now() - so.placed_at < interval '7 days' THEN CASE WHEN so.r_status < 0.5 THEN 'shipped' ELSE 'delivered' END
          WHEN so.r_status < 0.01 THEN 'pending'                 -- abandoned, never paid
          WHEN so.r_status < 0.07 THEN 'cancelled'
          WHEN so.r_status < 0.10 THEN 'refunded'
          ELSE 'delivered'
        END)::sales.order_status,
       jsonb_strip_nulls(jsonb_build_object(
           'channel', (ARRAY['web','app','app','mweb'])[1 + floor(so.r_channel * 4)::int],
           'device',  CASE WHEN so.r_channel < 0.25 THEN 'desktop' WHEN so.r_channel < 0.6 THEN 'android' ELSE 'ios' END,
           'utm',     CASE WHEN so.g % 3 = 0 THEN jsonb_build_object('source', (ARRAY['google','facebook','email','instagram'])[1 + so.g % 4], 'campaign', 'cmp_' || (so.g % 12)) END,
           'gift_wrap', CASE WHEN so.g % 17 = 0 THEN true END
       )),
       CASE WHEN so.g % 23 = 0 THEN (ARRAY['Leave at the door','Call before delivery','Deliver after 6 PM','Gift - hide the invoice'])[1 + so.g % 4] END,
       so.placed_at,
       so.placed_at
FROM seed_orders so
LEFT JOIN core.addresses a ON a.user_id = so.user_id AND a.is_default
ORDER BY so.placed_at;

-- 1-5 items per order; popular variants are picked more often (power(random(), 2))
INSERT INTO sales.order_items (order_id, variant_id, seller_id, quantity, unit_price, discount)
SELECT pick.order_id, v.variant_id, p.seller_id, pick.quantity,
       p.base_price + v.price_delta,
       CASE WHEN pick.r_disc < 0.1 THEN round((p.base_price + v.price_delta) * 0.05, 2) ELSE 0 END
FROM (
    SELECT DISTINCT ON (o.order_id, variant_id) o.order_id, variant_id, quantity, r_disc
    FROM sales.orders o
    CROSS JOIN LATERAL (
        SELECT 1 + floor((SELECT max(variant_id) FROM catalog.product_variants) * power(random(), 2))::bigint AS variant_id,
               CASE WHEN random() < 0.8 THEN 1 WHEN random() < 0.75 THEN 2 ELSE 3 END AS quantity,
               random() AS r_disc
        FROM generate_series(1, (ARRAY[1,1,1,2,2,2,3,3,4,5])[1 + (o.order_id * 7919 % 10)::int])
    ) items
) pick
JOIN catalog.product_variants v ON v.variant_id = pick.variant_id
JOIN catalog.products p ON p.product_id = v.product_id;

UPDATE sales.orders o
SET subtotal = t.subtotal
FROM (SELECT order_id, sum(line_total) AS subtotal FROM sales.order_items GROUP BY order_id) t
WHERE t.order_id = o.order_id;

-- ~15% of orders used a platform coupon that was valid when the order was placed
WITH chosen AS (
    SELECT o.order_id, o.user_id, o.placed_at, c.coupon_id,
           round(least(o.subtotal,
                       CASE c.discount_type
                         WHEN 'percent' THEN least(o.subtotal * c.discount_value / 100, coalesce(c.max_discount, o.subtotal))
                         ELSE c.discount_value END), 2) AS discount
    FROM sales.orders o
    CROSS JOIN LATERAL (
        SELECT * FROM sales.coupons c
        WHERE c.seller_id IS NULL AND c.is_active
          AND c.valid_during @> o.placed_at
          AND c.min_order_amount <= o.subtotal
        ORDER BY md5(o.order_id::text || c.coupon_id)
        LIMIT 1
    ) c
    WHERE o.order_id % 7 = 0 AND o.status <> 'pending'
), upd AS (
    UPDATE sales.orders o
    SET coupon_id = ch.coupon_id, discount_total = ch.discount
    FROM chosen ch
    WHERE ch.order_id = o.order_id
)
INSERT INTO sales.coupon_redemptions (coupon_id, user_id, order_id, discount_amount, redeemed_at)
SELECT coupon_id, user_id, order_id, discount, placed_at FROM chosen;

-- Shipping is free above 499 or for Prime members; 5% tax on the discounted amount
UPDATE sales.orders o
SET shipping_fee = CASE WHEN o.subtotal >= 499 OR u.is_prime THEN 0 ELSE 49 END,
    tax_total    = round((o.subtotal - o.discount_total) * 0.05, 2)
FROM core.users u
WHERE u.user_id = o.user_id;

-- Status history: replay each order's lifecycle up to its final status
INSERT INTO sales.order_status_history (order_id, from_status, to_status, changed_at)
SELECT o.order_id,
       lag(st.status) OVER (PARTITION BY o.order_id ORDER BY st.step),
       st.status,
       least(now(), o.placed_at + (st.step - 1) * interval '19 hours' + random() * interval '5 hours')
FROM sales.orders o
CROSS JOIN LATERAL unnest(
    CASE o.status
      WHEN 'pending'   THEN ARRAY['pending']::sales.order_status[]
      WHEN 'paid'      THEN ARRAY['pending','paid']::sales.order_status[]
      WHEN 'packed'    THEN ARRAY['pending','paid','packed']::sales.order_status[]
      WHEN 'shipped'   THEN ARRAY['pending','paid','packed','shipped']::sales.order_status[]
      WHEN 'delivered' THEN ARRAY['pending','paid','packed','shipped','delivered']::sales.order_status[]
      WHEN 'cancelled' THEN ARRAY['pending','cancelled']::sales.order_status[]
      WHEN 'refunded'  THEN ARRAY['pending','paid','packed','shipped','delivered','refunded']::sales.order_status[]
    END) WITH ORDINALITY AS st(status, step);

UPDATE sales.orders o
SET updated_at = h.last_change
FROM (SELECT order_id, max(changed_at) AS last_change FROM sales.order_status_history GROUP BY order_id) h
WHERE h.order_id = o.order_id;
