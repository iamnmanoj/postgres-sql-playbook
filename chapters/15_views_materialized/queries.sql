-- =====================================================================
--  Chapter 15 · Views & materialized views
--  Objects are created in schema "reporting" (idempotent).
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS reporting;

-- =====================================================================
-- SECTION: Plain views
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q15.01] Save a query under a name
-- Keywords: CREATE VIEW, CREATE OR REPLACE VIEW
-- Business question: Analysts keep re-writing the same order + customer + address join.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reporting.order_summary AS
SELECT o.order_id, o.order_number, o.placed_at, o.status, o.grand_total,
       u.user_id, u.full_name AS customer, u.is_prime,
       a.city, a.state,
       o.metadata ->> 'channel' AS channel
FROM sales.orders o
JOIN core.users u ON u.user_id = o.user_id
LEFT JOIN core.addresses a ON a.address_id = o.shipping_address_id;

SELECT city, count(*) AS orders, sum(grand_total) AS revenue
FROM reporting.order_summary
WHERE status = 'delivered' AND placed_at >= now() - interval '30 days'
GROUP BY city
ORDER BY revenue DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q15.02] A view is just a stored query — the planner expands it
-- Keywords: view expansion, pg_get_viewdef(), EXPLAIN on a view
-- ---------------------------------------------------------------------
SELECT pg_get_viewdef('reporting.order_summary'::regclass, true) AS definition;
EXPLAIN (COSTS OFF) SELECT order_number FROM reporting.order_summary WHERE order_id = 42;

-- ---------------------------------------------------------------------
-- [Q15.03] Views built on views, with aggregation
-- Keywords: view on view, aggregate view
-- Business question: A daily KPI view used by the dashboard.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reporting.daily_kpis AS
SELECT placed_at::date AS day,
       count(*)                                        AS orders,
       count(*) FILTER (WHERE status = 'cancelled')    AS cancelled,
       sum(grand_total) FILTER (WHERE status <> 'cancelled') AS gmv,
       round(avg(grand_total), 2)                      AS aov,
       count(DISTINCT user_id)                         AS buyers
FROM reporting.order_summary
GROUP BY placed_at::date;
SELECT * FROM reporting.daily_kpis ORDER BY day DESC LIMIT 7;

-- ---------------------------------------------------------------------
-- [Q15.04] Changing a view: OR REPLACE can only ADD columns at the end
-- Keywords: CREATE OR REPLACE VIEW limits, DROP VIEW, dependent objects
-- ---------------------------------------------------------------------
DO $$
BEGIN
    EXECUTE 'CREATE OR REPLACE VIEW reporting.order_summary AS SELECT order_id FROM sales.orders';
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;
DO $$
BEGIN
    EXECUTE 'DROP VIEW reporting.order_summary';                -- daily_kpis depends on it
EXCEPTION WHEN dependent_objects_still_exist THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

-- =====================================================================
-- SECTION: Updatable views
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q15.05] Simple views are automatically updatable
-- Keywords: updatable view, INSERT/UPDATE through a view
-- Business question: Give the support team a view of ACTIVE coupons they can edit.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reporting.active_coupons AS
SELECT coupon_id, code, description, discount_type, discount_value, valid_during, is_active
FROM sales.coupons
WHERE is_active;
BEGIN;
UPDATE reporting.active_coupons SET description = 'Edited via view' WHERE code = 'WELCOME10'
RETURNING coupon_id, description;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q15.06] Prevent writes that would "disappear" from the view
-- Keywords: WITH CHECK OPTION, LOCAL, CASCADED
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reporting.active_coupons_checked AS
SELECT coupon_id, code, description, is_active
FROM sales.coupons
WHERE is_active
WITH CASCADED CHECK OPTION;
DO $$
BEGIN
    UPDATE reporting.active_coupons_checked SET is_active = false WHERE code = 'WELCOME10';   -- would vanish
EXCEPTION WHEN with_check_option_violation THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- [Q15.07] Which views can be written to?
-- Keywords: information_schema.views, is_updatable, is_insertable_into
-- ---------------------------------------------------------------------
SELECT table_name, is_updatable, is_insertable_into, check_option
FROM information_schema.views
WHERE table_schema = 'reporting'
ORDER BY table_name;

-- =====================================================================
-- SECTION: Views & security
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q15.08] Expose only some columns/rows (a simple security boundary)
-- Keywords: column hiding, security_barrier
-- Business question: Marketing may see customers' city and Prime status, but never emails or phones.
-- Note: security_barrier stops user-supplied functions in WHERE from being pushed below the view's filter
--       (which could otherwise leak hidden rows).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reporting.marketing_customers WITH (security_barrier = true) AS
SELECT u.user_id, split_part(u.full_name, ' ', 1) AS first_name, u.is_prime, a.city, a.state, u.created_at::date AS signup_date
FROM core.users u
LEFT JOIN core.addresses a ON a.user_id = u.user_id AND a.is_default
WHERE u.status = 'active';
SELECT * FROM reporting.marketing_customers LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q15.09] Run a view with the CALLER's permissions (PG15+)
-- Keywords: security_invoker, ALTER VIEW … SET
-- Note: By default a view accesses base tables with the VIEW OWNER's privileges.
--       security_invoker = true makes RLS and GRANTs of the querying user apply (ch19).
-- ---------------------------------------------------------------------
ALTER VIEW reporting.marketing_customers SET (security_invoker = true);
SELECT relname, reloptions FROM pg_class WHERE relname = 'marketing_customers';

-- ---------------------------------------------------------------------
-- [Q15.10] A recursive view
-- Keywords: CREATE RECURSIVE VIEW
-- Business question: A permanent "category path" lookup for the storefront.
-- ---------------------------------------------------------------------
CREATE OR REPLACE RECURSIVE VIEW reporting.category_paths (category_id, name, path, depth) AS
SELECT category_id, name, name::text, 0 FROM catalog.categories WHERE parent_id IS NULL
UNION ALL
SELECT c.category_id, c.name, p.path || ' › ' || c.name, p.depth + 1
FROM catalog.categories c JOIN category_paths p ON c.parent_id = p.category_id;   -- self-reference is UNqualified
SELECT path FROM reporting.category_paths WHERE depth = 2 ORDER BY path LIMIT 6;

-- =====================================================================
-- SECTION: Materialized views
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q15.11] Store a query's RESULT for fast reads
-- Keywords: CREATE MATERIALIZED VIEW, IF NOT EXISTS
-- Business question: Seller dashboard metrics are expensive; precompute them.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS reporting.seller_stats AS
SELECT s.seller_id, s.store_name,
       count(DISTINCT oi.order_id)                                  AS orders,
       COALESCE(sum(oi.line_total) FILTER (WHERE o.status = 'delivered'), 0) AS delivered_revenue,
       round(avg(r.rating), 2)                                      AS avg_rating,
       now()                                                        AS refreshed_at
FROM core.sellers s
LEFT JOIN sales.order_items oi ON oi.seller_id = s.seller_id
LEFT JOIN sales.orders o ON o.order_id = oi.order_id
LEFT JOIN LATERAL (SELECT avg(rv.rating) AS rating
                   FROM catalog.reviews rv JOIN catalog.products p USING (product_id)
                   WHERE p.seller_id = s.seller_id) r ON true
GROUP BY s.seller_id, s.store_name;
SELECT store_name, orders, delivered_revenue, avg_rating FROM reporting.seller_stats ORDER BY delivered_revenue DESC LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q15.12] Materialized views can be indexed like tables
-- Keywords: CREATE UNIQUE INDEX on materialized view
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ix15_seller_stats_pk ON reporting.seller_stats (seller_id);
CREATE INDEX IF NOT EXISTS ix15_seller_stats_revenue ON reporting.seller_stats (delivered_revenue DESC);
EXPLAIN (COSTS OFF) SELECT * FROM reporting.seller_stats WHERE seller_id = 7;

-- ---------------------------------------------------------------------
-- [Q15.13] Refresh — data is a snapshot until you do
-- Keywords: REFRESH MATERIALIZED VIEW
-- ---------------------------------------------------------------------
SELECT max(refreshed_at) AS before_refresh FROM reporting.seller_stats;
REFRESH MATERIALIZED VIEW reporting.seller_stats;          -- locks out readers while it runs
SELECT max(refreshed_at) AS after_refresh FROM reporting.seller_stats;

-- ---------------------------------------------------------------------
-- [Q15.14] Refresh without blocking readers
-- Keywords: REFRESH MATERIALIZED VIEW CONCURRENTLY (needs a UNIQUE index)
-- ---------------------------------------------------------------------
REFRESH MATERIALIZED VIEW CONCURRENTLY reporting.seller_stats;

-- ---------------------------------------------------------------------
-- [Q15.15] Create now, fill later
-- Keywords: WITH NO DATA, ispopulated
-- Business question: Deploy a heavy monthly cohort matview during the day, populate it at night.
-- ---------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS reporting.monthly_category_sales;
CREATE MATERIALIZED VIEW reporting.monthly_category_sales AS
SELECT date_trunc('month', o.placed_at)::date AS month, c.name AS category, sum(oi.line_total) AS revenue
FROM sales.order_items oi
JOIN sales.orders o USING (order_id)
JOIN catalog.product_variants v USING (variant_id)
JOIN catalog.products p USING (product_id)
JOIN catalog.categories c USING (category_id)
WHERE o.status = 'delivered'
GROUP BY 1, 2
WITH NO DATA;
SELECT matviewname, ispopulated FROM pg_matviews WHERE schemaname = 'reporting';
DO $$
BEGIN
    PERFORM * FROM reporting.monthly_category_sales;
EXCEPTION WHEN object_not_in_prerequisite_state THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;
REFRESH MATERIALIZED VIEW reporting.monthly_category_sales;
SELECT * FROM reporting.monthly_category_sales ORDER BY month DESC, revenue DESC LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q15.16] Catalog of views and their dependencies
-- Keywords: pg_views, pg_matviews, pg_depend, pg_rewrite
-- Business question: If I change sales.orders, which views are affected?
-- ---------------------------------------------------------------------
SELECT schemaname, viewname FROM pg_views WHERE schemaname = 'reporting' ORDER BY viewname;
SELECT DISTINCT dependent.relname AS dependent_view, dependent.relkind
FROM pg_depend d
JOIN pg_rewrite rw ON rw.oid = d.objid
JOIN pg_class dependent ON dependent.oid = rw.ev_class
WHERE d.refobjid = 'sales.orders'::regclass
  AND dependent.oid <> 'sales.orders'::regclass
ORDER BY 1;
