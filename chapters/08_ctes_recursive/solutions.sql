-- =====================================================================
--  Chapter 08 · Solutions — CTEs & recursion
-- =====================================================================

-- [E08.01] Brand ratings via CTE
-- Keywords: WITH
WITH brand_rating AS (
    SELECT p.brand_id, avg(r.rating) AS avg_rating, count(*) AS reviews
    FROM catalog.reviews r JOIN catalog.products p USING (product_id)
    WHERE p.brand_id IS NOT NULL
    GROUP BY p.brand_id
)
SELECT b.name, round(br.avg_rating, 2) AS avg_rating, br.reviews
FROM brand_rating br JOIN catalog.brands b USING (brand_id)
WHERE br.avg_rating > 3.9
ORDER BY br.avg_rating DESC;

-- [E08.02] Repeat buyers per city
-- Keywords: chained CTEs
WITH recent_orders AS (
    SELECT user_id FROM sales.orders WHERE placed_at >= now() - interval '180 days'
), per_user AS (
    SELECT user_id, count(*) AS orders FROM recent_orders GROUP BY user_id
), repeat_buyers AS (
    SELECT user_id FROM per_user WHERE orders >= 3
)
SELECT a.city, count(*) AS repeat_buyers
FROM repeat_buyers rb
JOIN core.addresses a ON a.user_id = rb.user_id AND a.is_default
GROUP BY a.city
ORDER BY repeat_buyers DESC;

-- [E08.03] Leaf categories under Fashion with paths
-- Keywords: WITH RECURSIVE, NOT EXISTS
WITH RECURSIVE t AS (
    SELECT category_id, name, name AS path FROM catalog.categories WHERE slug = 'fashion'
    UNION ALL
    SELECT c.category_id, c.name, t.path || ' / ' || c.name
    FROM catalog.categories c JOIN t ON c.parent_id = t.category_id
)
SELECT path
FROM t
WHERE NOT EXISTS (SELECT 1 FROM catalog.categories ch WHERE ch.parent_id = t.category_id)
ORDER BY path;

-- [E08.04] Month names from a recursive counter
-- Keywords: WITH RECURSIVE, make_date(), to_char()
WITH RECURSIVE m(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM m WHERE n < 12)
SELECT n, trim(to_char(make_date(2025, n, 1), 'Month')) AS month_name FROM m;

-- [E08.05] Referral downline, depth-first
-- Keywords: WITH RECURSIVE, SEARCH DEPTH FIRST BY
WITH RECURSIVE down AS (
    SELECT user_id, full_name, 1 AS level FROM core.users WHERE referred_by = 108
    UNION ALL
    SELECT u.user_id, u.full_name, d.level + 1
    FROM core.users u JOIN down d ON u.referred_by = d.user_id
) SEARCH DEPTH FIRST BY user_id SET ord
SELECT repeat('  ', level - 1) || full_name AS member, level
FROM down
ORDER BY ord;

-- [E08.06] Cancel stale orders + write history in one statement
-- Keywords: data-modifying CTE, UPDATE … RETURNING, INSERT … SELECT
BEGIN;
WITH cancelled AS (
    UPDATE sales.orders
    SET status = 'cancelled', updated_at = now()
    WHERE status = 'pending' AND placed_at < now() - interval '30 days'
    RETURNING order_id
), logged AS (
    INSERT INTO sales.order_status_history (order_id, from_status, to_status)
    SELECT order_id, 'pending', 'cancelled' FROM cancelled
    RETURNING 1
)
SELECT count(*) AS cancelled_orders FROM logged;
ROLLBACK;
