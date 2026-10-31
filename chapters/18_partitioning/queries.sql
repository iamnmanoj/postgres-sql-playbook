-- =====================================================================
--  Chapter 18 · Table partitioning
--  analytics.events is a real RANGE-partitioned table (monthly). We only READ its
--  structure and add future partitions idempotently. LIST/HASH/attach/detach demos
--  live in schema playground_18.
-- =====================================================================
DROP SCHEMA IF EXISTS playground_18 CASCADE;
CREATE SCHEMA playground_18;

-- =====================================================================
-- SECTION: Exploring a partitioned table
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q18.01] What does a partitioned table look like?
-- Keywords: PARTITION BY RANGE, pg_partition_tree(), relkind 'p', pg_get_partkeydef(), pg_get_expr(relpartbound)
-- ---------------------------------------------------------------------
SELECT pg_get_partkeydef('analytics.events'::regclass) AS partition_key;
SELECT relid::regclass AS partition, parentrelid::regclass AS parent, isleaf, level
FROM pg_partition_tree('analytics.events')
ORDER BY relid::regclass::text
LIMIT 6;
SELECT c.relname, pg_get_expr(c.relpartbound, c.oid) AS bounds
FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'analytics.events'::regclass
ORDER BY c.relname DESC
LIMIT 4;

-- ---------------------------------------------------------------------
-- [Q18.02] Where do the rows actually live?
-- Keywords: tableoid, tableoid::regclass
-- Business question: Events per monthly partition.
-- ---------------------------------------------------------------------
SELECT tableoid::regclass AS partition, count(*) AS events, min(occurred_at)::date AS first, max(occurred_at)::date AS last
FROM analytics.events
GROUP BY tableoid
ORDER BY partition DESC
LIMIT 6;

-- ---------------------------------------------------------------------
-- [Q18.03] Partition pruning: only the relevant partitions are scanned
-- Keywords: partition pruning, enable_partition_pruning, EXPLAIN
-- ---------------------------------------------------------------------
EXPLAIN (COSTS OFF)
SELECT count(*) FROM analytics.events
WHERE occurred_at >= date_trunc('month', now()) AND occurred_at < date_trunc('month', now()) + interval '1 month';
DO $$                                                                         -- no key filter → ALL partitions
DECLARE line text; scans int := 0;
BEGIN
    FOR line IN EXECUTE 'EXPLAIN SELECT count(*) FROM analytics.events WHERE event_type = ''purchase''' LOOP
        IF line ~ 'Scan on events_' THEN scans := scans + 1; END IF;
    END LOOP;
    RAISE NOTICE 'Without a filter on occurred_at the plan scans % partitions', scans;
END $$;

-- ---------------------------------------------------------------------
-- [Q18.04] Run-time pruning with parameters
-- Keywords: Subplans Removed, PREPARE, EXECUTE, plan_cache_mode
-- ---------------------------------------------------------------------
PREPARE events_since(timestamptz) AS
    SELECT count(*) FROM analytics.events WHERE occurred_at >= $1;
SET plan_cache_mode = force_generic_plan;
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF) EXECUTE events_since(now() - interval '10 days');
RESET plan_cache_mode;
DEALLOCATE events_since;

-- =====================================================================
-- SECTION: Managing RANGE partitions
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q18.05] Create next quarter's partitions ahead of time (idempotent)
-- Keywords: CREATE TABLE … PARTITION OF … FOR VALUES FROM … TO, IF NOT EXISTS, format() %I %L
-- Note: if the DEFAULT partition already held rows for that range, creation would fail (Q18.06).
-- ---------------------------------------------------------------------
DO $$
DECLARE m date;
BEGIN
    FOR m IN SELECT generate_series(date_trunc('month', now() + interval '3 months'),
                                    date_trunc('month', now() + interval '5 months'), interval '1 month')::date
    LOOP
        EXECUTE format('CREATE TABLE IF NOT EXISTS analytics.%I PARTITION OF analytics.events FOR VALUES FROM (%L) TO (%L)',
                       'events_' || to_char(m, 'YYYY_MM'), m, (m + interval '1 month')::date);
    END LOOP;
END $$;
SELECT count(*) AS partitions_now FROM pg_inherits WHERE inhparent = 'analytics.events'::regclass;

-- ---------------------------------------------------------------------
-- [Q18.06] The DEFAULT partition catches rows that fit nowhere else
-- Keywords: DEFAULT partition, no partition of relation found for row
-- Business question: A buggy client sends events dated 2099 — where do they go?
-- ---------------------------------------------------------------------
BEGIN;
INSERT INTO analytics.events (session_id, event_type, occurred_at)
VALUES (gen_random_uuid(), 'page_view', '2099-01-01')
RETURNING tableoid::regclass AS stored_in;
DO $$
BEGIN
    CREATE TABLE analytics.events_2099_01 PARTITION OF analytics.events FOR VALUES FROM ('2099-01-01') TO ('2099-02-01');
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;    -- default already contains a row for that range
END $$;
ROLLBACK;

-- =====================================================================
-- SECTION: LIST and HASH partitioning
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q18.07] LIST partitioning by discrete values
-- Keywords: PARTITION BY LIST, FOR VALUES IN, INSERT … SELECT routing
-- Business question: Store an order archive split by sales region.
-- ---------------------------------------------------------------------
CREATE TABLE playground_18.orders_by_region (
    order_id    bigint NOT NULL,
    region      text   NOT NULL,
    state       text,
    grand_total numeric(12, 2),
    placed_at   timestamptz
) PARTITION BY LIST (region);
CREATE TABLE playground_18.orders_south PARTITION OF playground_18.orders_by_region FOR VALUES IN ('south');
CREATE TABLE playground_18.orders_west  PARTITION OF playground_18.orders_by_region FOR VALUES IN ('west');
CREATE TABLE playground_18.orders_north PARTITION OF playground_18.orders_by_region FOR VALUES IN ('north');
CREATE TABLE playground_18.orders_other PARTITION OF playground_18.orders_by_region DEFAULT;
INSERT INTO playground_18.orders_by_region
SELECT o.order_id,
       CASE WHEN a.state IN ('Karnataka', 'Tamil Nadu', 'Kerala', 'Telangana') THEN 'south'
            WHEN a.state IN ('Maharashtra', 'Gujarat', 'Rajasthan') THEN 'west'
            WHEN a.state IN ('Delhi', 'Uttar Pradesh', 'Chandigarh') THEN 'north'
            ELSE 'east/central' END,
       a.state, o.grand_total, o.placed_at
FROM sales.orders o JOIN core.addresses a ON a.address_id = o.shipping_address_id;
SELECT tableoid::regclass AS partition, count(*) FROM playground_18.orders_by_region GROUP BY 1 ORDER BY 1;

-- ---------------------------------------------------------------------
-- [Q18.08] HASH partitioning spreads rows evenly
-- Keywords: PARTITION BY HASH, MODULUS, REMAINDER
-- Business question: Spread cart events across 4 partitions by user_id (no natural range).
-- ---------------------------------------------------------------------
CREATE TABLE playground_18.cart_activity (user_id bigint NOT NULL, variant_id bigint, at timestamptz) PARTITION BY HASH (user_id);
CREATE TABLE playground_18.cart_activity_p0 PARTITION OF playground_18.cart_activity FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE playground_18.cart_activity_p1 PARTITION OF playground_18.cart_activity FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE playground_18.cart_activity_p2 PARTITION OF playground_18.cart_activity FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE playground_18.cart_activity_p3 PARTITION OF playground_18.cart_activity FOR VALUES WITH (MODULUS 4, REMAINDER 3);
INSERT INTO playground_18.cart_activity
SELECT c.user_id, ci.variant_id, ci.added_at FROM sales.cart_items ci JOIN sales.carts c USING (cart_id);
SELECT tableoid::regclass AS partition, count(*) FROM playground_18.cart_activity GROUP BY 1 ORDER BY 1;
EXPLAIN (COSTS OFF) SELECT * FROM playground_18.cart_activity WHERE user_id = 42;     -- one partition

-- ---------------------------------------------------------------------
-- [Q18.09] Sub-partitioning: partitions that are themselves partitioned
-- Keywords: multi-level partitioning, PARTITION OF … PARTITION BY
-- Business question: Payments by year, then by method.
-- ---------------------------------------------------------------------
CREATE TABLE playground_18.payments_archive (payment_id bigint, method text NOT NULL, amount numeric, created_at timestamptz NOT NULL)
    PARTITION BY RANGE (created_at);
CREATE TABLE playground_18.payments_y2025 PARTITION OF playground_18.payments_archive
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01') PARTITION BY LIST (method);
CREATE TABLE playground_18.payments_y2025_upi   PARTITION OF playground_18.payments_y2025 FOR VALUES IN ('upi');
CREATE TABLE playground_18.payments_y2025_other PARTITION OF playground_18.payments_y2025 DEFAULT;
INSERT INTO playground_18.payments_archive
SELECT payment_id, method::text, amount, created_at FROM sales.payments
WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01';
SELECT relid::regclass, level, isleaf FROM pg_partition_tree('playground_18.payments_archive');

-- =====================================================================
-- SECTION: Keys, indexes, row movement
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q18.10] Indexes on the parent cascade to all partitions; unique keys must include the partition key
-- Keywords: CREATE INDEX on partitioned table, partitioned index, PRIMARY KEY must include partition key
-- ---------------------------------------------------------------------
CREATE INDEX ON playground_18.orders_by_region (placed_at);
SELECT tablename, indexname FROM pg_indexes WHERE schemaname = 'playground_18' AND indexdef LIKE '%placed_at%' ORDER BY 1;
DO $$
BEGIN
    ALTER TABLE playground_18.orders_by_region ADD PRIMARY KEY (order_id);          -- missing "region"
EXCEPTION WHEN feature_not_supported OR invalid_table_definition THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;
ALTER TABLE playground_18.orders_by_region ADD PRIMARY KEY (order_id, region);      -- OK

-- ---------------------------------------------------------------------
-- [Q18.11] Updating the partition key moves the row to another partition
-- Keywords: row movement, UPDATE of partition key
-- ---------------------------------------------------------------------
SELECT order_id, region, tableoid::regclass AS before FROM playground_18.orders_by_region WHERE region = 'south' LIMIT 1 \gset
UPDATE playground_18.orders_by_region SET region = 'west' WHERE order_id = :order_id
RETURNING order_id, region, tableoid::regclass AS after;

-- ---------------------------------------------------------------------
-- [Q18.12] Navigate the hierarchy
-- Keywords: pg_partition_root(), pg_partition_ancestors(), pg_inherits
-- ---------------------------------------------------------------------
SELECT pg_partition_root('playground_18.payments_y2025_upi') AS root;
SELECT * FROM pg_partition_ancestors('playground_18.payments_y2025_upi');

-- =====================================================================
-- SECTION: Attach, detach, retention
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q18.13] Load a table separately, then ATTACH it as a partition
-- Keywords: ATTACH PARTITION, CHECK constraint to skip validation scan
-- Business question: Bulk-load a year of archived page views offline, then plug it in instantly.
-- ---------------------------------------------------------------------
CREATE TABLE playground_18.page_views (viewed_at timestamptz NOT NULL, path text) PARTITION BY RANGE (viewed_at);
CREATE TABLE playground_18.page_views_2024 (LIKE playground_18.page_views);
INSERT INTO playground_18.page_views_2024
SELECT ts, '/p/' || (random() * 3000)::int FROM generate_series('2024-01-01'::timestamptz, '2024-12-31', interval '1 hour') ts;
ALTER TABLE playground_18.page_views_2024
    ADD CONSTRAINT y2024 CHECK (viewed_at >= '2024-01-01' AND viewed_at < '2025-01-01');   -- lets ATTACH skip the scan
ALTER TABLE playground_18.page_views ATTACH PARTITION playground_18.page_views_2024
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
ALTER TABLE playground_18.page_views_2024 DROP CONSTRAINT y2024;                         -- now redundant
SELECT count(*) AS rows_via_parent FROM playground_18.page_views;

-- ---------------------------------------------------------------------
-- [Q18.14] Data retention: detach or drop old partitions instead of DELETE
-- Keywords: DETACH PARTITION, DETACH PARTITION … CONCURRENTLY, DROP TABLE partition
-- Note: DETACH CONCURRENTLY (PG14+) avoids blocking queries but can't run inside a transaction block.
-- ---------------------------------------------------------------------
CREATE TABLE playground_18.page_views_2025 PARTITION OF playground_18.page_views FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
ALTER TABLE playground_18.page_views DETACH PARTITION playground_18.page_views_2024 CONCURRENTLY;   -- now a normal table
SELECT count(*) AS rows_via_parent_after_detach FROM playground_18.page_views;
SELECT count(*) AS rows_in_detached_table FROM playground_18.page_views_2024;
DROP TABLE playground_18.page_views_2024;                                                  -- instant "DELETE" of a year

-- ---------------------------------------------------------------------
-- [Q18.15] Find empty / old partitions of the real events table (retention candidates)
-- Keywords: pg_class.reltuples, pg_stat_user_tables per partition
-- ---------------------------------------------------------------------
SELECT c.relname AS partition, pg_get_expr(c.relpartbound, c.oid) AS bounds, s.n_live_tup AS approx_rows,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS size
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
JOIN pg_stat_user_tables s ON s.relid = c.oid
WHERE i.inhparent = 'analytics.events'::regclass
ORDER BY c.relname
LIMIT 6;

-- =====================================================================
-- SECTION: Performance features
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q18.16] Partition-wise aggregation and joins
-- Keywords: enable_partitionwise_aggregate, enable_partitionwise_join
-- ---------------------------------------------------------------------
BEGIN;
SET LOCAL enable_partitionwise_aggregate = on;
EXPLAIN (COSTS OFF)
SELECT region, count(*) FROM playground_18.orders_by_region GROUP BY region;   -- aggregate per partition, then append
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q18.17] The older mechanism: table inheritance
-- Keywords: INHERITS, ONLY
-- Note: Before PG10, partitioning was built with INHERITS + CHECK + triggers. Still used for other purposes.
-- ---------------------------------------------------------------------
CREATE TABLE playground_18.base_note (id int, body text);
CREATE TABLE playground_18.order_note (order_id bigint) INHERITS (playground_18.base_note);
INSERT INTO playground_18.base_note VALUES (1, 'generic');
INSERT INTO playground_18.order_note VALUES (2, 'about an order', 42);
SELECT count(*) AS incl_children FROM playground_18.base_note;
SELECT count(*) AS only_parent FROM ONLY playground_18.base_note;
