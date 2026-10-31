-- =====================================================================
--  Chapter 20 · Solutions — advanced extras
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS tablefunc;

-- [E20.01] Coupons valid during the next 30 days
-- Keywords: tstzrange(), &&
SELECT code, valid_during && tstzrange(now(), now() + interval '30 days') AS usable_next_30_days
FROM sales.coupons
ORDER BY usable_next_30_days DESC, code
LIMIT 10;

-- [E20.02] Payout coverage as a multirange
-- Keywords: range_agg(), lower(), upper()
SELECT range_agg(period) AS coverage, lower(range_agg(period)) AS first_day, upper(range_agg(period)) AS last_day
FROM core.seller_payouts
WHERE seller_id = 85;

-- [E20.03] Sampled discount share
-- Keywords: TABLESAMPLE BERNOULLI
SELECT round(100.0 * count(*) FILTER (WHERE discount > 0) / count(*), 1) AS pct_with_discount_sample,
       count(*) AS sampled_rows
FROM sales.order_items TABLESAMPLE BERNOULLI (5) REPEATABLE (7);

-- [E20.04] Columns and indexes per table from pg_catalog
-- Keywords: pg_class, pg_attribute, pg_index
SELECT c.relname,
       (SELECT count(*) FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) AS columns,
       (SELECT count(*) FROM pg_index i WHERE i.indrelid = c.oid) AS indexes
FROM pg_class c
WHERE c.relnamespace = 'catalog'::regnamespace AND c.relkind = 'r'
ORDER BY c.relname;

-- [E20.05] Paging with a cursor
-- Keywords: DECLARE, FETCH
BEGIN;
DECLARE newest_reviews CURSOR FOR SELECT review_id, rating, created_at FROM catalog.reviews ORDER BY created_at DESC;
FETCH 5 FROM newest_reviews;
FETCH 5 FROM newest_reviews;
CLOSE newest_reviews;
COMMIT;

-- [E20.06] crosstab pivot
-- Keywords: crosstab() with category query
SELECT *
FROM crosstab(
    $$ SELECT rating::int, CASE WHEN body IS NULL THEN 'without_body' ELSE 'with_body' END, count(*)
       FROM catalog.reviews GROUP BY 1, 2 ORDER BY 1, 2 $$,
    $$ VALUES ('with_body'), ('without_body') $$
) AS t(rating int, with_body bigint, without_body bigint);
