-- =====================================================================
--  Chapter 07 · Solutions — subqueries & set operations
-- =====================================================================

-- [E07.01] Largest order via scalar subquery
-- Keywords: scalar subquery, max()
SELECT order_number, grand_total
FROM sales.orders
WHERE grand_total = (SELECT max(grand_total) FROM sales.orders);

-- [E07.02] Products with photo reviews
-- Keywords: EXISTS, cardinality()
SELECT p.product_id, p.name
FROM catalog.products p
WHERE EXISTS (SELECT 1 FROM catalog.reviews r
              WHERE r.product_id = p.product_id AND cardinality(r.image_urls) > 0)
LIMIT 10;

-- [E07.03] Unstocked variants
-- Keywords: NOT EXISTS
SELECT v.variant_id, v.sku
FROM catalog.product_variants v
WHERE NOT EXISTS (SELECT 1 FROM logistics.inventory i WHERE i.variant_id = v.variant_id);

-- [E07.04] Above-average buyers
-- Keywords: correlated scalar subquery, derived table, scalar subquery in WHERE
SELECT *
FROM (SELECT u.user_id, u.full_name,
             (SELECT count(*) FROM sales.orders o WHERE o.user_id = u.user_id) AS orders
      FROM core.users u) t
WHERE orders > (SELECT count(*)::numeric / count(DISTINCT user_id) FROM sales.orders)
ORDER BY orders DESC
LIMIT 10;

-- [E07.05] Never-redeemed coupons
-- Keywords: EXCEPT
SELECT code FROM sales.coupons
EXCEPT
SELECT c.code FROM sales.coupons c JOIN sales.coupon_redemptions r USING (coupon_id)
ORDER BY code;

-- [E07.06] Happy reviewers who still returned something
-- Keywords: INTERSECT
SELECT user_id FROM catalog.reviews WHERE rating = 5
INTERSECT
SELECT o.user_id FROM sales.returns r
JOIN sales.order_items oi USING (order_item_id)
JOIN sales.orders o USING (order_id)
ORDER BY user_id
LIMIT 10;

-- [E07.07] Personal-record orders
-- Keywords: > ALL (correlated subquery)
SELECT o.user_id, o.order_number, o.grand_total, o.placed_at
FROM sales.orders o
WHERE o.grand_total > ALL (SELECT prev.grand_total FROM sales.orders prev
                           WHERE prev.user_id = o.user_id AND prev.placed_at < o.placed_at)
  AND EXISTS (SELECT 1 FROM sales.orders prev WHERE prev.user_id = o.user_id AND prev.placed_at < o.placed_at)
ORDER BY o.placed_at DESC
LIMIT 10;

-- [E07.08] Attention list via UNION ALL
-- Keywords: UNION ALL, type alignment
SELECT 'stale_pending_order' AS kind, order_id AS ref_id, placed_at AS since
FROM sales.orders WHERE status = 'pending' AND placed_at < now() - interval '2 days'
UNION ALL
SELECT 'lost_shipment', shipment_id, shipped_at
FROM logistics.shipments WHERE status = 'lost'
UNION ALL
SELECT 'slow_return', return_id, requested_at
FROM sales.returns WHERE status = 'requested' AND requested_at < now() - interval '5 days'
ORDER BY since
LIMIT 20;
