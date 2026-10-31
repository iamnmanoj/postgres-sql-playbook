-- =====================================================================
--  Chapter 14 · Indexes & performance
--  Creates indexes named ix14_* (idempotent). EXPLAIN output varies a little
--  between runs/machines — focus on the plan SHAPE (node types).
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS btree_gist;
ANALYZE;

-- =====================================================================
-- SECTION: Reading plans
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q14.01] See the plan the optimizer chose (estimates only, query not run)
-- Keywords: EXPLAIN, Seq Scan, cost, rows, width
-- Note: cost=startup..total (arbitrary units), rows = estimated rows, width = avg row bytes.
-- ---------------------------------------------------------------------
EXPLAIN SELECT * FROM sales.payments WHERE amount > 100000;

-- ---------------------------------------------------------------------
-- [Q14.02] Run the query and compare estimates with reality
-- Keywords: EXPLAIN ANALYZE, actual time, loops, BUFFERS, shared hit/read
-- Note: EXPLAIN ANALYZE really executes the statement — wrap DML in BEGIN/ROLLBACK!
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT status, count(*) FROM sales.orders GROUP BY status;

-- ---------------------------------------------------------------------
-- [Q14.03] Machine-readable plans and extra detail
-- Keywords: EXPLAIN (FORMAT JSON), VERBOSE, SETTINGS, SUMMARY
-- ---------------------------------------------------------------------
EXPLAIN (FORMAT JSON, VERBOSE, SETTINGS, SUMMARY)
SELECT order_number FROM sales.orders WHERE order_id = 42;

-- ---------------------------------------------------------------------
-- [Q14.04] Join algorithms: Nested Loop, Hash Join, Merge Join
-- Keywords: Nested Loop, Hash Join, Merge Join, enable_hashjoin, enable_nestloop
-- Note: enable_* settings are for EXPERIMENTS ONLY — never in production.
-- ---------------------------------------------------------------------
EXPLAIN (COSTS OFF)
SELECT o.order_number, u.email FROM sales.orders o JOIN core.users u USING (user_id) WHERE o.order_id < 50;   -- nested loop
EXPLAIN (COSTS OFF)
SELECT u.status, count(*) FROM sales.orders o JOIN core.users u USING (user_id) GROUP BY u.status;            -- hash join
BEGIN;
SET LOCAL enable_hashjoin = off;
SET LOCAL enable_nestloop = off;
EXPLAIN (COSTS OFF)
SELECT u.status, count(*) FROM sales.orders o JOIN core.users u USING (user_id) GROUP BY u.status;            -- merge join
ROLLBACK;

-- =====================================================================
-- SECTION: B-tree indexes
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q14.05] Single-column index: Seq Scan → Index Scan
-- Keywords: CREATE INDEX, IF NOT EXISTS, Index Scan, Bitmap Heap Scan
-- Business question: Find a payment by gateway reference quickly (support tickets do this all day).
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS ix14_refunds_payment_id;                                     -- start clean (re-runs)
EXPLAIN (COSTS OFF) SELECT * FROM sales.refunds WHERE payment_id = 1234;          -- before: Seq Scan
CREATE INDEX IF NOT EXISTS ix14_refunds_payment_id ON sales.refunds (payment_id);
EXPLAIN (COSTS OFF) SELECT * FROM sales.refunds WHERE payment_id = 1234;          -- after: Index Scan

-- ---------------------------------------------------------------------
-- [Q14.06] Multi-column index: column ORDER matters (equality first, then range/sort)
-- Keywords: composite index, leftmost prefix
-- Business question: "My orders" page: one user's orders, newest first.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix14_orders_user_placed ON sales.orders (user_id, placed_at DESC);
EXPLAIN (COSTS OFF)
SELECT order_number, placed_at FROM sales.orders WHERE user_id = 42 ORDER BY placed_at DESC LIMIT 10;   -- no Sort node
EXPLAIN (COSTS OFF)
SELECT count(*) FROM sales.orders WHERE placed_at > now() - interval '1 day';  -- can't use (user_id, …) for this

-- ---------------------------------------------------------------------
-- [Q14.07] Index-only scans with a covering index
-- Keywords: INCLUDE, Index Only Scan, visibility map, Heap Fetches
-- Business question: Order list with just number + total, without touching the table.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix14_orders_user_cover ON sales.orders (user_id) INCLUDE (order_number, grand_total, status);
VACUUM (ANALYZE) sales.orders;                                   -- sets the visibility map
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT order_number, grand_total FROM sales.orders WHERE user_id = 42;

-- ---------------------------------------------------------------------
-- [Q14.08] Partial index: index only the rows you query
-- Keywords: partial index, CREATE INDEX … WHERE
-- Business question: The ops dashboard polls orders that are not finished yet (a tiny fraction).
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix14_orders_open ON sales.orders (placed_at)
    WHERE status IN ('pending', 'paid', 'packed', 'shipped');
EXPLAIN (COSTS OFF)
SELECT order_id FROM sales.orders WHERE status IN ('pending', 'paid', 'packed', 'shipped') ORDER BY placed_at LIMIT 20;
SELECT pg_size_pretty(pg_relation_size('ix14_orders_open'::regclass))          AS partial_index_size,
       pg_size_pretty(pg_relation_size('sales.orders_placed_at_idx'::regclass)) AS full_index_size;

-- ---------------------------------------------------------------------
-- [Q14.09] Expression index: index the result of a function
-- Keywords: expression index, lower(), IMMUTABLE requirement
-- Business question: Look up sellers by case-insensitive store name.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix14_sellers_lower_name ON core.sellers (lower(store_name));
ANALYZE core.sellers;
EXPLAIN (COSTS OFF) SELECT seller_id FROM core.sellers WHERE lower(store_name) = 'urban mart 175';
EXPLAIN (COSTS OFF) SELECT seller_id FROM core.sellers WHERE store_name ILIKE 'urban mart 175';   -- not used

-- ---------------------------------------------------------------------
-- [Q14.10] Unique indexes enforce rules (and can be partial)
-- Keywords: CREATE UNIQUE INDEX
-- Business question: Coupon codes must be unique among ACTIVE coupons only.
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ix14_coupons_active_code ON sales.coupons (lower(code::text)) WHERE is_active;
SELECT indexname, indexdef FROM pg_indexes WHERE indexname = 'ix14_coupons_active_code';

-- ---------------------------------------------------------------------
-- [Q14.11] Sorting and LIMIT benefit from index order
-- Keywords: ORDER BY … LIMIT, Incremental Sort, top-N heapsort
-- ---------------------------------------------------------------------
EXPLAIN (COSTS OFF) SELECT * FROM sales.orders ORDER BY placed_at DESC LIMIT 5;            -- index backward scan
EXPLAIN (COSTS OFF) SELECT * FROM sales.orders ORDER BY grand_total DESC LIMIT 5;          -- top-N heapsort

-- =====================================================================
-- SECTION: Other index types
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q14.12] GIN for JSONB: default jsonb_ops vs smaller jsonb_path_ops
-- Keywords: USING gin, jsonb_ops, jsonb_path_ops, @>
-- Business question: Filter orders by metadata quickly (channel/device/utm).
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix14_orders_metadata_gin  ON sales.orders USING gin (metadata);                 -- supports @>, ?, ?|, ?&
CREATE INDEX IF NOT EXISTS ix14_orders_metadata_path ON sales.orders USING gin (metadata jsonb_path_ops);  -- only @>, smaller/faster
ANALYZE sales.orders;
EXPLAIN (COSTS OFF) SELECT count(*) FROM sales.orders WHERE metadata @> '{"utm": {"source": "instagram"}}';
SELECT indexrelid::regclass AS index, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_index WHERE indexrelid::regclass::text LIKE 'ix14_orders_metadata%';

-- ---------------------------------------------------------------------
-- [Q14.13] GIN for arrays
-- Keywords: GIN on array column, @>, &&
-- Business question: Fast tag filters on the catalog.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix14_products_tags ON catalog.products USING gin (tags);
ANALYZE catalog.products;
BEGIN;
SET LOCAL enable_seqscan = off;            -- small table: force the index to show it CAN be used
EXPLAIN (COSTS OFF) SELECT name FROM catalog.products WHERE tags @> ARRAY['gift', 'premium'];
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q14.14] GiST for ranges (and the index behind EXCLUDE constraints)
-- Keywords: USING gist, range operators &&, @>
-- Business question: Which coupons are valid right now?
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix14_coupons_valid_during ON sales.coupons USING gist (valid_during);
BEGIN;
SET LOCAL enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT code FROM sales.coupons WHERE valid_during @> now();
ROLLBACK;
SELECT indexname FROM pg_indexes WHERE tablename = 'seller_payouts';      -- the EXCLUDE constraint's GiST index

-- ---------------------------------------------------------------------
-- [Q14.15] BRIN: a tiny index for naturally ordered, huge tables
-- Keywords: USING brin, pages_per_range, block ranges
-- Business question: Time-range queries on shipment events (inserted in time order).
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix14_shipment_events_brin ON logistics.shipment_events USING brin (occurred_at) WITH (pages_per_range = 32);
CREATE INDEX IF NOT EXISTS ix14_shipment_events_btree ON logistics.shipment_events (occurred_at);
ANALYZE logistics.shipment_events;
SELECT pg_size_pretty(pg_relation_size('ix14_shipment_events_brin'::regclass))  AS brin_size,
       pg_size_pretty(pg_relation_size('ix14_shipment_events_btree'::regclass)) AS btree_size;
DROP INDEX ix14_shipment_events_btree;
EXPLAIN (COSTS OFF)
SELECT status, count(*) FROM logistics.shipment_events WHERE occurred_at >= now() - interval '1 day' GROUP BY status;

-- ---------------------------------------------------------------------
-- [Q14.16] Hash index (equality only)
-- Keywords: USING hash
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix14_payments_provider_hash ON sales.payments USING hash (provider_ref);
ANALYZE sales.payments;
EXPLAIN (COSTS OFF) SELECT payment_id FROM sales.payments WHERE provider_ref = 'pay_0123456789abcd';

-- =====================================================================
-- SECTION: Index maintenance
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q14.17] Build/rebuild without blocking writes
-- Keywords: CREATE INDEX CONCURRENTLY, REINDEX CONCURRENTLY, DROP INDEX CONCURRENTLY
-- Note: CONCURRENTLY can't run inside a transaction block; if it fails it leaves an INVALID index to drop.
-- ---------------------------------------------------------------------
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix14_reviews_user_id ON catalog.reviews (user_id);
REINDEX INDEX CONCURRENTLY ix14_reviews_user_id;
SELECT indexrelid::regclass, indisvalid, indisready FROM pg_index WHERE indexrelid = 'ix14_reviews_user_id'::regclass;

-- ---------------------------------------------------------------------
-- [Q14.18] Find foreign keys without a supporting index
-- Keywords: pg_constraint, contype = 'f', conkey, pg_index.indkey
-- Business question: Deleting a user scans every child table that lacks an index on user_id.
-- ---------------------------------------------------------------------
SELECT c.conrelid::regclass AS table_name, c.conname, a.attname AS fk_column
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
WHERE c.contype = 'f'
  AND c.connamespace::regnamespace::text IN ('core', 'catalog', 'logistics', 'sales')
  AND NOT EXISTS (SELECT 1 FROM pg_index i
                  WHERE i.indrelid = c.conrelid AND i.indkey[0] = c.conkey[1])
ORDER BY 1, 2;

-- ---------------------------------------------------------------------
-- [Q14.19] Which indexes are used — and which are dead weight?
-- Keywords: pg_stat_user_indexes, idx_scan, pg_relation_size()
-- ---------------------------------------------------------------------
SELECT schemaname || '.' || relname AS table_name, indexrelname AS index_name, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname IN ('core', 'catalog', 'logistics', 'sales')
ORDER BY idx_scan, pg_relation_size(indexrelid) DESC
LIMIT 10;

-- =====================================================================
-- SECTION: Statistics, VACUUM and sizes
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q14.20] Planner statistics and bad estimates
-- Keywords: ANALYZE, pg_stats, n_distinct, most_common_vals, CREATE STATISTICS
-- Business question: city and state are correlated (Mumbai ⇒ Maharashtra) — the planner multiplies their
--                    selectivities and underestimates the combined filter (≈90 rows estimated vs 560 actual).
-- ---------------------------------------------------------------------
DROP STATISTICS IF EXISTS ix14_addresses_city_state;                                   -- start clean (re-runs)
ANALYZE core.addresses;
SELECT attname, n_distinct, most_common_vals::text AS mcv
FROM pg_stats WHERE schemaname = 'core' AND tablename = 'addresses' AND attname IN ('city', 'state');
EXPLAIN (ANALYZE, COSTS ON, TIMING OFF, SUMMARY OFF)
SELECT * FROM core.addresses WHERE city = 'Mumbai' AND state = 'Maharashtra';        -- estimate too low
CREATE STATISTICS IF NOT EXISTS ix14_addresses_city_state (dependencies) ON city, state FROM core.addresses;
ANALYZE core.addresses;
EXPLAIN (ANALYZE, COSTS ON, TIMING OFF, SUMMARY OFF)
SELECT * FROM core.addresses WHERE city = 'Mumbai' AND state = 'Maharashtra';        -- estimate fixed

-- ---------------------------------------------------------------------
-- [Q14.21] Dead tuples, VACUUM and autovacuum
-- Keywords: VACUUM, VACUUM (VERBOSE, ANALYZE), n_dead_tup, last_autovacuum, pg_stat_user_tables
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS playground_14;
DROP TABLE IF EXISTS playground_14.bloat_demo;
CREATE TABLE playground_14.bloat_demo AS SELECT g AS id, md5(g::text) AS payload FROM generate_series(1, 50000) g;
UPDATE playground_14.bloat_demo SET payload = upper(payload);                 -- 50k dead row versions
SELECT pg_stat_force_next_flush();
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relid = 'playground_14.bloat_demo'::regclass;
VACUUM (ANALYZE) playground_14.bloat_demo;
SELECT pg_stat_force_next_flush();
SELECT n_live_tup, n_dead_tup, last_vacuum IS NOT NULL AS vacuumed
FROM pg_stat_user_tables WHERE relid = 'playground_14.bloat_demo'::regclass;
SELECT relname, n_dead_tup, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables WHERE schemaname = 'sales' ORDER BY n_dead_tup DESC LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q14.22] How big are things?
-- Keywords: pg_size_pretty(), pg_relation_size(), pg_indexes_size(), pg_total_relation_size(), pg_database_size()
-- ---------------------------------------------------------------------
SELECT c.oid::regclass AS table_name,
       pg_size_pretty(pg_relation_size(c.oid))       AS table_only,
       pg_size_pretty(pg_indexes_size(c.oid))        AS indexes,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_incl_toast
FROM pg_class c
WHERE c.relkind = 'r' AND c.relnamespace::regnamespace::text IN ('core', 'catalog', 'logistics', 'sales')
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 6;
SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;

-- =====================================================================
-- SECTION: Query tuning patterns
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q14.23] Non-sargable predicates hide indexes — rewrite them
-- Keywords: sargable, function on column, range rewrite
-- Business question: Orders placed today.
-- ---------------------------------------------------------------------
EXPLAIN (COSTS OFF) SELECT count(*) FROM sales.orders WHERE placed_at::date = current_date;          -- reads EVERYTHING + Filter
EXPLAIN (COSTS OFF) SELECT count(*) FROM sales.orders
WHERE placed_at >= current_date AND placed_at < current_date + 1;                                     -- Index Cond: reads only today

-- ---------------------------------------------------------------------
-- [Q14.24] Deep OFFSET vs keyset pagination
-- Keywords: OFFSET cost, keyset pagination, rows removed
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT order_id FROM sales.orders ORDER BY placed_at DESC, order_id DESC OFFSET 25000 LIMIT 20;
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT order_id FROM sales.orders
WHERE placed_at < now() - interval '600 days'
ORDER BY placed_at DESC LIMIT 20;

-- ---------------------------------------------------------------------
-- [Q14.25] Memory for sorts and hashes
-- Keywords: work_mem, external merge Disk, Sort Method
-- ---------------------------------------------------------------------
BEGIN;
SET LOCAL work_mem = '64kB';
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT * FROM sales.order_items ORDER BY line_total DESC OFFSET 70000 LIMIT 1;    -- Sort Method: external merge
SET LOCAL work_mem = '64MB';
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT * FROM sales.order_items ORDER BY line_total DESC OFFSET 70000 LIMIT 1;    -- Sort Method: quicksort (in memory)
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q14.26] Find the most expensive queries across the whole system
-- Keywords: pg_stat_statements, total_exec_time, calls, mean_exec_time, pg_stat_statements_reset()
-- ---------------------------------------------------------------------
SELECT calls, round(total_exec_time::numeric, 1) AS total_ms, round(mean_exec_time::numeric, 2) AS mean_ms,
       rows, left(regexp_replace(query, '\s+', ' ', 'g'), 70) AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q14.27] Parallel query
-- Keywords: Gather, Parallel Seq Scan, max_parallel_workers_per_gather
-- ---------------------------------------------------------------------
BEGIN;
SET LOCAL parallel_setup_cost = 0;
SET LOCAL parallel_tuple_cost = 0;
SET LOCAL min_parallel_table_scan_size = 0;
EXPLAIN (COSTS OFF) SELECT sum(line_total) FROM sales.order_items;
ROLLBACK;
SHOW max_parallel_workers_per_gather;
