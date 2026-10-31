-- =====================================================================
--  Chapter 06 · Solutions — joins
-- =====================================================================

-- [E06.01] Recent reviews with names
-- Keywords: JOIN, ORDER BY, LIMIT
SELECT r.created_at, p.name AS product, u.full_name AS reviewer, r.rating
FROM catalog.reviews r
JOIN catalog.products p ON p.product_id = r.product_id
JOIN core.users u ON u.user_id = r.user_id
ORDER BY r.created_at DESC
LIMIT 10;

-- [E06.02] Stock per warehouse, including empty ones
-- Keywords: LEFT JOIN, COALESCE(), sum()
SELECT w.code, COALESCE(sum(i.quantity_on_hand), 0) AS units
FROM logistics.warehouses w
LEFT JOIN logistics.inventory i ON i.warehouse_id = w.warehouse_id
GROUP BY w.code
ORDER BY units DESC;

-- [E06.03] Sellers with products but no sales (returns 0 rows on the seed data: every seller with products has sold something)
-- Keywords: JOIN, LEFT JOIN … IS NULL, DISTINCT
SELECT DISTINCT s.seller_id, s.store_name
FROM core.sellers s
JOIN catalog.products p ON p.seller_id = s.seller_id
LEFT JOIN sales.order_items oi ON oi.seller_id = s.seller_id
WHERE oi.order_item_id IS NULL;

-- [E06.04] Recent orders with optional shipments
-- Keywords: LEFT JOIN, multiple joins
SELECT o.order_number, a.city, sh.carrier, sh.status AS shipment_status
FROM sales.orders o
LEFT JOIN core.addresses a ON a.address_id = o.shipping_address_id
LEFT JOIN logistics.shipments sh ON sh.order_id = o.order_id
WHERE o.placed_at >= now() - interval '7 days'
ORDER BY o.placed_at DESC
LIMIT 20;

-- [E06.05] Cart users who never ordered
-- Keywords: JOIN, anti-join
SELECT DISTINCT c.user_id
FROM sales.carts c
JOIN sales.cart_items ci ON ci.cart_id = c.cart_id
LEFT JOIN sales.orders o ON o.user_id = c.user_id
WHERE o.order_id IS NULL
LIMIT 20;

-- [E06.06] Best seller per leaf category
-- Keywords: JOIN LATERAL, ORDER BY … LIMIT 1
SELECT c.name AS category, best.name AS product, best.units
FROM catalog.categories c
JOIN LATERAL (
    SELECT p.name, sum(oi.quantity) AS units
    FROM catalog.products p
    JOIN catalog.product_variants v ON v.product_id = p.product_id
    JOIN sales.order_items oi ON oi.variant_id = v.variant_id
    WHERE p.category_id = c.category_id
    GROUP BY p.product_id, p.name
    ORDER BY units DESC
    LIMIT 1
) best ON true
ORDER BY best.units DESC;

-- [E06.07] Coupon validity audit
-- Keywords: JOIN, NOT (range @> value)
SELECT o.order_number, c.code, o.placed_at, c.valid_during
FROM sales.orders o
JOIN sales.coupons c ON c.coupon_id = o.coupon_id
WHERE NOT (c.valid_during @> o.placed_at);

-- [E06.08] Zero-filled weekly series
-- Keywords: generate_series(), LEFT JOIN, date_trunc()
SELECT w::date AS week_start, count(o.order_id) AS app_orders
FROM generate_series(date_trunc('week', now()) - interval '7 weeks', date_trunc('week', now()), interval '1 week') AS w
LEFT JOIN sales.orders o
       ON date_trunc('week', o.placed_at) = w
      AND o.metadata->>'channel' = 'app'
GROUP BY w
ORDER BY w;

-- [E06.09] Same referrer, same signup day
-- Keywords: self join, a.id < b.id
SELECT a.referred_by AS referrer, a.user_id AS user_a, b.user_id AS user_b, a.created_at::date AS signup_day
FROM core.users a
JOIN core.users b
  ON b.referred_by = a.referred_by
 AND b.created_at::date = a.created_at::date
 AND a.user_id < b.user_id
ORDER BY signup_day DESC
LIMIT 10;
