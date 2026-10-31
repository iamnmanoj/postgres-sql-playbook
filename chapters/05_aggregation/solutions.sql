-- =====================================================================
--  Chapter 05 · Solutions — aggregation & grouping
-- =====================================================================

-- [E05.01] Products per brand
-- Keywords: JOIN, GROUP BY, count()
SELECT b.name, count(*) AS products
FROM catalog.products p
JOIN catalog.brands b USING (brand_id)
GROUP BY b.name
ORDER BY products DESC;

-- [E05.02] Refunds per reason with HAVING
-- Keywords: GROUP BY, HAVING, sum()
SELECT reason, count(*) AS refunds, sum(amount) AS refunded
FROM sales.refunds
GROUP BY reason
HAVING count(*) > 50
ORDER BY refunded DESC;

-- [E05.03] Warehouse stock summary
-- Keywords: count(), sum(), NULLIF(), round()
SELECT w.code,
       count(*)                     AS variants,
       sum(i.quantity_on_hand)      AS on_hand,
       sum(i.quantity_reserved)     AS reserved,
       round(100.0 * sum(i.quantity_reserved) / NULLIF(sum(i.quantity_on_hand), 0), 2) AS pct_reserved
FROM logistics.inventory i
JOIN logistics.warehouses w USING (warehouse_id)
GROUP BY w.code
ORDER BY w.code;

-- [E05.04] New users and Prime users per month
-- Keywords: date_trunc(), FILTER
SELECT date_trunc('month', created_at)::date AS month,
       count(*) AS new_users,
       count(*) FILTER (WHERE is_prime) AS new_prime_users
FROM core.users
WHERE created_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1
ORDER BY 1;

-- [E05.05] Brand ratings
-- Keywords: percentile_cont() WITHIN GROUP, avg(), HAVING
SELECT b.name,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY r.rating) AS median_rating,
       round(avg(r.rating), 2) AS avg_rating,
       count(*) AS reviews
FROM catalog.reviews r
JOIN catalog.products p USING (product_id)
JOIN catalog.brands b USING (brand_id)
GROUP BY b.name
HAVING count(*) >= 200
ORDER BY avg_rating DESC;

-- [E05.06] Payment methods per order status
-- Keywords: array_agg(DISTINCT …)
SELECT o.status, array_agg(DISTINCT p.method ORDER BY p.method) AS methods
FROM sales.orders o
JOIN sales.payments p USING (order_id)
GROUP BY o.status
ORDER BY o.status;

-- [E05.07] Top-5 seller leaderboard as one JSON object
-- Keywords: jsonb_object_agg(), derived table, LIMIT
SELECT jsonb_object_agg(store_name, revenue) AS leaderboard
FROM (
    SELECT s.store_name, sum(oi.line_total) AS revenue
    FROM sales.order_items oi
    JOIN sales.orders o USING (order_id)
    JOIN core.sellers s ON s.seller_id = oi.seller_id
    WHERE o.status = 'delivered'
    GROUP BY s.store_name
    ORDER BY revenue DESC
    LIMIT 5
) top5;

-- [E05.08] Revenue by root and leaf category with ROLLUP
-- Keywords: ROLLUP, GROUPING(), COALESCE(), self-join
SELECT CASE WHEN GROUPING(root.name) = 1 THEN 'GRAND TOTAL' ELSE root.name END AS root_category,
       CASE WHEN GROUPING(leaf.name) = 1 AND GROUPING(root.name) = 0 THEN 'subtotal' ELSE leaf.name END AS leaf_category,
       sum(oi.line_total) AS revenue
FROM sales.order_items oi
JOIN sales.orders o USING (order_id)
JOIN catalog.product_variants v USING (variant_id)
JOIN catalog.products p USING (product_id)
JOIN catalog.categories leaf ON leaf.category_id = p.category_id
LEFT JOIN catalog.categories mid ON mid.category_id = leaf.parent_id
LEFT JOIN catalog.categories top ON top.category_id = mid.parent_id
JOIN catalog.categories root ON root.category_id = COALESCE(top.category_id, mid.category_id, leaf.category_id)
WHERE o.status = 'delivered'
GROUP BY ROLLUP (root.name, leaf.name)
ORDER BY root.name NULLS LAST, leaf.name NULLS LAST;

-- [E05.09] Coupon effectiveness with share of total
-- Keywords: sum(), avg(), scalar subquery
SELECT c.code,
       count(*) AS redemptions,
       sum(r.discount_amount) AS total_discount,
       round(avg(r.discount_amount), 2) AS avg_discount,
       round(100 * sum(r.discount_amount) / (SELECT sum(discount_amount) FROM sales.coupon_redemptions), 1) AS pct_of_all_discount
FROM sales.coupon_redemptions r
JOIN sales.coupons c USING (coupon_id)
GROUP BY c.code
ORDER BY total_discount DESC
LIMIT 10;
