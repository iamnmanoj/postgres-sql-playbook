-- =====================================================================
--  Chapter 02 · Seed data for ShopSphere (run by scripts/reset.sh)
--  Generates a realistic, reproducible data set using generate_series(),
--  random() (seeded with setseed) and INSERT ... SELECT.
--  \ir = "include file relative to this one" (a psql meta-command).
-- =====================================================================
\set ON_ERROR_STOP on
SET search_path = core, catalog, logistics, sales, audit, analytics, public;
SET client_min_messages = warning;
-- Same "random" data on every rebuild. (\gset stores the result in a psql variable, hiding the output.)
SELECT setseed(0.42) AS seeded \gset

\ir seed/00_lookups.sql
\ir seed/01_users_sellers.sql
\ir seed/02_catalog_inventory.sql
\ir seed/03_coupons_orders.sql
\ir seed/04_payments_shipping.sql
\ir seed/05_reviews_engagement.sql

ANALYZE;                       -- refresh planner statistics after bulk load

-- Row counts per table, so you can see what was generated
SELECT schemaname || '.' || relname AS table_name, n_live_tup AS approx_rows
FROM pg_stat_user_tables
WHERE schemaname IN ('core', 'catalog', 'logistics', 'sales', 'audit', 'analytics')
  AND n_live_tup > 0
ORDER BY schemaname, relname;
