-- =====================================================================
--  Chapter 08 · Common Table Expressions (WITH) & recursive queries
--  Data-modifying examples are wrapped in BEGIN … ROLLBACK.
-- =====================================================================

-- =====================================================================
-- SECTION: Basic CTEs
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q08.01] Name a subquery and use it like a table
-- Keywords: WITH, AS (CTE)
-- Business question: Revenue per seller last 90 days, then only the top 5.
-- ---------------------------------------------------------------------
WITH seller_revenue AS (
    SELECT oi.seller_id, sum(oi.line_total) AS revenue
    FROM sales.order_items oi
    JOIN sales.orders o USING (order_id)
    WHERE o.status IN ('delivered', 'shipped') AND o.placed_at >= now() - interval '90 days'
    GROUP BY oi.seller_id
)
SELECT s.store_name, r.revenue
FROM seller_revenue r
JOIN core.sellers s USING (seller_id)
ORDER BY r.revenue DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q08.02] Chain CTEs: each one can use the previous ones
-- Keywords: multiple CTEs, chained WITH
-- Business question: Customer segments by lifetime value (RFM-lite): spend → tier → tier sizes.
-- ---------------------------------------------------------------------
WITH customer_spend AS (
    SELECT user_id, sum(grand_total) AS ltv, count(*) AS orders, max(placed_at) AS last_order
    FROM sales.orders
    WHERE status = 'delivered'
    GROUP BY user_id
), tiered AS (
    SELECT *, CASE WHEN ltv >= 1000000 THEN 'platinum'
                   WHEN ltv >= 300000  THEN 'gold'
                   WHEN ltv >= 50000   THEN 'silver'
                   ELSE 'bronze' END AS tier
    FROM customer_spend
)
SELECT tier, count(*) AS customers, round(avg(ltv)) AS avg_ltv, round(avg(orders), 1) AS avg_orders
FROM tiered
GROUP BY tier
ORDER BY avg_ltv DESC;

-- ---------------------------------------------------------------------
-- [Q08.03] Reference the same CTE more than once
-- Keywords: CTE reuse, CROSS JOIN with a one-row CTE
-- Business question: Each category's share of total delivered revenue.
-- ---------------------------------------------------------------------
WITH cat_rev AS (
    SELECT p.category_id, sum(oi.line_total) AS revenue
    FROM sales.order_items oi
    JOIN sales.orders o USING (order_id)
    JOIN catalog.product_variants v USING (variant_id)
    JOIN catalog.products p USING (product_id)
    WHERE o.status = 'delivered'
    GROUP BY p.category_id
), total AS (
    SELECT sum(revenue) AS all_revenue FROM cat_rev       -- 1st use
)
SELECT c.name, r.revenue, round(100 * r.revenue / t.all_revenue, 2) AS pct
FROM cat_rev r                                            -- 2nd use
JOIN catalog.categories c USING (category_id)
CROSS JOIN total t
ORDER BY pct DESC
LIMIT 8;

-- ---------------------------------------------------------------------
-- [Q08.04] Control whether a CTE is computed once (materialized) or inlined
-- Keywords: MATERIALIZED, NOT MATERIALIZED
-- Note: Since PG12, a CTE used once is inlined (optimised with the outer query);
--       MATERIALIZED forces a one-time "optimisation fence", NOT MATERIALIZED forces inlining.
-- ---------------------------------------------------------------------
EXPLAIN (COSTS OFF)
WITH recent AS MATERIALIZED (SELECT * FROM sales.orders WHERE placed_at >= now() - interval '7 days')
SELECT count(*) FROM recent WHERE user_id = 42;
EXPLAIN (COSTS OFF)
WITH recent AS NOT MATERIALIZED (SELECT * FROM sales.orders WHERE placed_at >= now() - interval '7 days')
SELECT count(*) FROM recent WHERE user_id = 42;

-- ---------------------------------------------------------------------
-- [Q08.05] A conversion funnel built step by step with CTEs
-- Keywords: CTE pipeline, count(DISTINCT), FILTER
-- Business question: Of last month's sessions, how many viewed a product, carted, checked out, purchased?
-- ---------------------------------------------------------------------
WITH sessions AS (
    SELECT session_id,
           bool_or(event_type = 'product_view')   AS viewed,
           bool_or(event_type = 'add_to_cart')    AS carted,
           bool_or(event_type = 'checkout_start') AS checked_out,
           bool_or(event_type = 'purchase')       AS purchased
    FROM analytics.events
    WHERE occurred_at >= now() - interval '30 days'
    GROUP BY session_id
), funnel AS (
    SELECT count(*) AS sessions,
           count(*) FILTER (WHERE viewed)      AS viewed,
           count(*) FILTER (WHERE carted)      AS carted,
           count(*) FILTER (WHERE checked_out) AS checked_out,
           count(*) FILTER (WHERE purchased)   AS purchased
    FROM sessions
)
SELECT *, round(100.0 * purchased / sessions, 2) AS conversion_pct FROM funnel;

-- =====================================================================
-- SECTION: Recursive CTEs
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q08.06] The simplest recursion: count to 10
-- Keywords: WITH RECURSIVE, UNION ALL, anchor member, recursive member
-- Note: anchor runs once; the recursive part runs repeatedly on the previous step's rows until it returns none.
-- ---------------------------------------------------------------------
WITH RECURSIVE counter(n) AS (
    SELECT 1                         -- anchor
    UNION ALL
    SELECT n + 1 FROM counter        -- recursive member
    WHERE n < 10                     -- stop condition!
)
SELECT array_agg(n) FROM counter;

-- ---------------------------------------------------------------------
-- [Q08.07] Walk DOWN a tree: all descendants of a category with depth
-- Keywords: WITH RECURSIVE, tree traversal, depth
-- Business question: Every category under "Electronics", with its level.
-- ---------------------------------------------------------------------
WITH RECURSIVE subtree AS (
    SELECT category_id, name, parent_id, 0 AS depth
    FROM catalog.categories
    WHERE slug = 'electronics'
    UNION ALL
    SELECT c.category_id, c.name, c.parent_id, s.depth + 1
    FROM catalog.categories c
    JOIN subtree s ON c.parent_id = s.category_id
)
SELECT repeat('    ', depth) || name AS category_tree, depth
FROM subtree
ORDER BY depth, name;

-- ---------------------------------------------------------------------
-- [Q08.08] Walk UP a tree: breadcrumbs for a product page
-- Keywords: WITH RECURSIVE, path building, string_agg
-- Business question: "Electronics › Audio › Headphones & Earbuds" for product 1.
-- ---------------------------------------------------------------------
WITH RECURSIVE crumbs AS (
    SELECT c.category_id, c.parent_id, c.name, 1 AS lvl
    FROM catalog.categories c
    JOIN catalog.products p ON p.category_id = c.category_id
    WHERE p.product_id = 1
    UNION ALL
    SELECT parent.category_id, parent.parent_id, parent.name, crumbs.lvl + 1
    FROM catalog.categories parent
    JOIN crumbs ON parent.category_id = crumbs.parent_id
)
SELECT string_agg(name, ' › ' ORDER BY lvl DESC) AS breadcrumb FROM crumbs;

-- ---------------------------------------------------------------------
-- [Q08.09] Full paths for every category, and roll revenue up the tree
-- Keywords: WITH RECURSIVE, array path, @> on arrays
-- Business question: Revenue for EVERY node including its whole subtree (Electronics = all electronics).
-- ---------------------------------------------------------------------
WITH RECURSIVE tree AS (
    SELECT category_id, name, ARRAY[category_id] AS path
    FROM catalog.categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.category_id, c.name, t.path || c.category_id
    FROM catalog.categories c JOIN tree t ON c.parent_id = t.category_id
), leaf_revenue AS (
    SELECT p.category_id, sum(oi.line_total) AS revenue
    FROM sales.order_items oi
    JOIN catalog.product_variants v USING (variant_id)
    JOIN catalog.products p USING (product_id)
    GROUP BY p.category_id
)
SELECT node.name, cardinality(node.path) AS level, sum(lr.revenue) AS subtree_revenue
FROM tree node
JOIN tree leaf ON leaf.path @> ARRAY[node.category_id]     -- leaf is inside node's subtree
JOIN leaf_revenue lr ON lr.category_id = leaf.category_id
GROUP BY node.category_id, node.name, node.path
ORDER BY node.path
LIMIT 15;

-- ---------------------------------------------------------------------
-- [Q08.10] Follow a chain of references: referral chains
-- Keywords: WITH RECURSIVE, chain, max depth
-- Business question: Who referred whom, up to the top, for user 4999?
-- ---------------------------------------------------------------------
WITH RECURSIVE chain AS (
    SELECT user_id, referred_by, full_name, 0 AS hops
    FROM core.users WHERE user_id = (SELECT max(user_id) FROM core.users WHERE referred_by IS NOT NULL)
    UNION ALL
    SELECT u.user_id, u.referred_by, u.full_name, c.hops + 1
    FROM core.users u JOIN chain c ON u.user_id = c.referred_by
)
SELECT hops, user_id, full_name FROM chain ORDER BY hops;

-- ---------------------------------------------------------------------
-- [Q08.11] Multi-level referral network size (all descendants per top referrer)
-- Keywords: WITH RECURSIVE, carrying the root id
-- Business question: Which users have the biggest referral "downline" (direct + indirect)?
-- ---------------------------------------------------------------------
WITH RECURSIVE downline AS (
    SELECT referred_by AS root_id, user_id, 1 AS level
    FROM core.users WHERE referred_by IS NOT NULL
    UNION ALL
    SELECT d.root_id, u.user_id, d.level + 1
    FROM core.users u JOIN downline d ON u.referred_by = d.user_id
    WHERE d.level < 10
)
SELECT root_id, count(*) AS network_size, max(level) AS deepest_level
FROM downline
GROUP BY root_id
ORDER BY network_size DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q08.12] Control traversal order
-- Keywords: SEARCH DEPTH FIRST BY, SEARCH BREADTH FIRST BY, SET
-- Business question: Print the whole category tree in "file explorer" (depth-first) order (PG14+).
-- ---------------------------------------------------------------------
WITH RECURSIVE tree AS (
    SELECT category_id, name, parent_id, 0 AS depth FROM catalog.categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.category_id, c.name, c.parent_id, t.depth + 1
    FROM catalog.categories c JOIN tree t ON c.parent_id = t.category_id
) SEARCH DEPTH FIRST BY name SET dfs_order
SELECT repeat('  ', depth) || name AS explorer_view
FROM tree
ORDER BY dfs_order
LIMIT 15;

WITH RECURSIVE tree AS (
    SELECT category_id, name, 0 AS depth FROM catalog.categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.category_id, c.name, t.depth + 1
    FROM catalog.categories c JOIN tree t ON c.parent_id = t.category_id
) SEARCH BREADTH FIRST BY name SET bfs_order
SELECT depth, name FROM tree ORDER BY bfs_order LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q08.13] Protect against cycles in graph data
-- Keywords: CYCLE … SET … USING, UNION (vs UNION ALL) in recursion
-- Business question: Warehouse transfer routes may loop (BLR→MUM→DEL→BLR). List reachable hubs safely (PG14+).
-- ---------------------------------------------------------------------
WITH RECURSIVE routes(src, dst) AS (
    VALUES ('BLR1', 'MUM1'), ('MUM1', 'DEL1'), ('DEL1', 'BLR1'), ('DEL1', 'KOL1')
), reach AS (
    SELECT src, dst, 1 AS hops FROM routes WHERE src = 'BLR1'
    UNION ALL
    SELECT r.src, r.dst, reach.hops + 1
    FROM routes r JOIN reach ON r.src = reach.dst
) CYCLE dst SET is_cycle USING path
SELECT dst AS reachable_hub, hops, path, is_cycle FROM reach ORDER BY hops;

-- ---------------------------------------------------------------------
-- [Q08.14] Recursive date series (alternative to generate_series)
-- Keywords: WITH RECURSIVE, date arithmetic
-- Business question: Next 5 payout dates: the 7th of each coming month.
-- ---------------------------------------------------------------------
WITH RECURSIVE payout_dates(d, n) AS (
    SELECT (date_trunc('month', current_date) + interval '1 month 6 days')::date, 1
    UNION ALL
    SELECT (d + interval '1 month')::date, n + 1 FROM payout_dates WHERE n < 5
)
SELECT d AS payout_date, to_char(d, 'Dy') AS weekday FROM payout_dates;

-- ---------------------------------------------------------------------
-- [Q08.15] Recursion that carries running state: compound coupon stacking
-- Keywords: WITH RECURSIVE, state accumulation
-- Business question: Applying 10%, then 5%, then flat ₹100 to a ₹5,000 cart, step by step.
-- ---------------------------------------------------------------------
WITH RECURSIVE discounts(step, kind, val) AS (
    VALUES (1, 'percent', 10), (2, 'percent', 5), (3, 'fixed', 100)
), apply(step, price) AS (
    SELECT 0, 5000::numeric
    UNION ALL
    SELECT d.step,
           round(CASE d.kind WHEN 'percent' THEN a.price * (1 - d.val / 100.0) ELSE a.price - d.val END, 2)
    FROM apply a JOIN discounts d ON d.step = a.step + 1
)
SELECT * FROM apply ORDER BY step;

-- =====================================================================
-- SECTION: Data-modifying CTEs
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q08.16] Move rows atomically: DELETE … RETURNING feeding an INSERT
-- Keywords: data-modifying CTE, DELETE … RETURNING, INSERT … SELECT
-- Business question: Archive read notifications older than 180 days into an archive table.
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS playground_08;
CREATE TABLE IF NOT EXISTS playground_08.notifications_archive (LIKE core.notifications);
BEGIN;
WITH moved AS (
    DELETE FROM core.notifications
    WHERE read_at IS NOT NULL AND sent_at < now() - interval '180 days'
    RETURNING *
)
INSERT INTO playground_08.notifications_archive
SELECT * FROM moved;
SELECT (SELECT count(*) FROM playground_08.notifications_archive) AS archived_rows;
ROLLBACK;                         -- keep the seed data intact

-- ---------------------------------------------------------------------
-- [Q08.17] Several writes in one statement, wired together with RETURNING
-- Keywords: INSERT … RETURNING in CTE, multi-table insert
-- Business question: Create a new customer, their default address and an empty cart in ONE statement.
-- ---------------------------------------------------------------------
BEGIN;
WITH new_user AS (
    INSERT INTO core.users (email, full_name)
    VALUES ('new.customer@example.com', 'New Customer')
    RETURNING user_id
), new_address AS (
    INSERT INTO core.addresses (user_id, line1, city, state, postal_code, is_default)
    SELECT user_id, '12 MG Road', 'Bengaluru', 'Karnataka', '560001', true FROM new_user
    RETURNING address_id, user_id
), new_cart AS (
    INSERT INTO sales.carts (user_id) SELECT user_id FROM new_user
    RETURNING cart_id
)
SELECT u.user_id, a.address_id, c.cart_id
FROM new_user u, new_address a, new_cart c;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q08.18] UPDATE in a CTE and report the before/after
-- Keywords: UPDATE … RETURNING in CTE, joining the result
-- Business question: Raise reorder levels for fast movers and report what changed.
-- ---------------------------------------------------------------------
BEGIN;
WITH fast_movers AS (
    SELECT variant_id FROM sales.order_items
    GROUP BY variant_id ORDER BY sum(quantity) DESC LIMIT 20
), bumped AS (
    UPDATE logistics.inventory i
    SET reorder_level = reorder_level * 2
    FROM fast_movers f
    WHERE i.variant_id = f.variant_id
    RETURNING i.variant_id, i.warehouse_id, i.reorder_level AS new_level
)
SELECT count(*) AS rows_updated, min(new_level), max(new_level) FROM bumped;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q08.19] Snapshot rule: all CTEs see the SAME snapshot (they can't see each other's writes)
-- Keywords: data-modifying CTE visibility
-- ---------------------------------------------------------------------
BEGIN;
WITH ins AS (
    INSERT INTO catalog.brands (name) VALUES ('Snapshot Demo Brand') RETURNING brand_id
)
SELECT (SELECT count(*) FROM catalog.brands WHERE name = 'Snapshot Demo Brand') AS visible_in_same_statement,  -- 0!
       (SELECT count(*) FROM ins) AS returned_by_cte;                                                       -- 1
ROLLBACK;
