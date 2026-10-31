-- =====================================================================
--  Chapter 15 · Solutions — views & materialized views
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS reporting;

-- [E15.01] Catalog view
-- Keywords: CREATE OR REPLACE VIEW
CREATE OR REPLACE VIEW reporting.ex15_product_catalog AS
SELECT p.product_id, p.name, b.name AS brand, c.name AS category, c.slug AS category_slug,
       s.store_name, p.base_price
FROM catalog.products p
LEFT JOIN catalog.brands b USING (brand_id)
JOIN catalog.categories c USING (category_id)
JOIN core.sellers s USING (seller_id)
WHERE p.is_active;
SELECT name, brand, store_name, base_price
FROM reporting.ex15_product_catalog
WHERE category_slug = 'laptops'
ORDER BY base_price
LIMIT 5;

-- [E15.02] Updatable view with LOCAL CHECK OPTION
-- Keywords: WITH LOCAL CHECK OPTION
CREATE OR REPLACE VIEW reporting.ex15_karnataka_addresses AS
SELECT address_id, user_id, line1, city, state, postal_code
FROM core.addresses
WHERE state = 'Karnataka'
WITH LOCAL CHECK OPTION;
DO $$
BEGIN
    UPDATE reporting.ex15_karnataka_addresses SET state = 'Kerala'
    WHERE address_id = (SELECT min(address_id) FROM reporting.ex15_karnataka_addresses);
EXCEPTION WHEN with_check_option_violation THEN
    RAISE NOTICE 'Blocked as expected: %', SQLERRM;
END $$;

-- [E15.03] Materialized view + unique index + concurrent refresh
-- Keywords: CREATE MATERIALIZED VIEW, CREATE UNIQUE INDEX, REFRESH … CONCURRENTLY
CREATE MATERIALIZED VIEW IF NOT EXISTS reporting.ex15_product_ratings AS
SELECT product_id, count(*) AS reviews, round(avg(rating), 2) AS avg_rating
FROM catalog.reviews
GROUP BY product_id;
CREATE UNIQUE INDEX IF NOT EXISTS ex15_product_ratings_pk ON reporting.ex15_product_ratings (product_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY reporting.ex15_product_ratings;

-- [E15.04] Best-rated products
-- Keywords: query a materialized view
SELECT p.name, r.reviews, r.avg_rating
FROM reporting.ex15_product_ratings r
JOIN catalog.products p USING (product_id)
WHERE r.reviews >= 20
ORDER BY r.avg_rating DESC, r.reviews DESC
LIMIT 5;

-- [E15.05] Views and matviews with sizes
-- Keywords: pg_class.relkind, pg_total_relation_size()
SELECT c.relname,
       CASE c.relkind WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized view' END AS kind,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS size     -- plain views have no storage
FROM pg_class c
WHERE c.relnamespace = 'reporting'::regnamespace AND c.relkind IN ('v', 'm')
ORDER BY kind, c.relname;
