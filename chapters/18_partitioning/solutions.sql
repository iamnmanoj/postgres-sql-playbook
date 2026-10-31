-- =====================================================================
--  Chapter 18 · Solutions — partitioning
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS playground_18;
DROP TABLE IF EXISTS playground_18.reviews_by_rating, playground_18.order_items_hash, playground_18.shipments_by_month;

-- [E18.01] Partition count and empty partitions
-- Keywords: pg_inherits, pg_stat_user_tables
SELECT count(*) AS partitions,
       count(*) FILTER (WHERE s.n_live_tup = 0) AS empty_partitions
FROM pg_inherits i
JOIN pg_stat_user_tables s ON s.relid = i.inhrelid
WHERE i.inhparent = 'analytics.events'::regclass;

-- [E18.02] Pruning to last month
-- Keywords: EXPLAIN, partition pruning
EXPLAIN (COSTS OFF)
SELECT count(*) FROM analytics.events
WHERE event_type = 'purchase'
  AND occurred_at >= date_trunc('month', now()) - interval '1 month'
  AND occurred_at <  date_trunc('month', now());

-- [E18.03] LIST partitions by rating
-- Keywords: PARTITION BY LIST, FOR VALUES IN
CREATE TABLE playground_18.reviews_by_rating (review_id bigint, product_id bigint, rating smallint NOT NULL, created_at timestamptz)
    PARTITION BY LIST (rating);
CREATE TABLE playground_18.reviews_negative PARTITION OF playground_18.reviews_by_rating FOR VALUES IN (1, 2);
CREATE TABLE playground_18.reviews_neutral  PARTITION OF playground_18.reviews_by_rating FOR VALUES IN (3);
CREATE TABLE playground_18.reviews_positive PARTITION OF playground_18.reviews_by_rating FOR VALUES IN (4, 5);
INSERT INTO playground_18.reviews_by_rating SELECT review_id, product_id, rating, created_at FROM catalog.reviews;
SELECT tableoid::regclass, count(*) FROM playground_18.reviews_by_rating GROUP BY 1 ORDER BY 1;

-- [E18.04] HASH into 8 partitions, generated with a loop
-- Keywords: PARTITION BY HASH, MODULUS, REMAINDER, dynamic SQL
CREATE TABLE playground_18.order_items_hash (order_id bigint NOT NULL, variant_id bigint, line_total numeric)
    PARTITION BY HASH (order_id);
DO $$
BEGIN
    FOR r IN 0..7 LOOP
        EXECUTE format('CREATE TABLE playground_18.%I PARTITION OF playground_18.order_items_hash FOR VALUES WITH (MODULUS 8, REMAINDER %s)',
                       'order_items_hash_p' || r, r);
    END LOOP;
END $$;
INSERT INTO playground_18.order_items_hash SELECT order_id, variant_id, line_total FROM sales.order_items;
SELECT min(cnt), max(cnt) FROM (SELECT tableoid, count(*) AS cnt FROM playground_18.order_items_hash GROUP BY tableoid) t;

-- [E18.05] Monthly RANGE partitions + DEFAULT for NULL keys
-- Keywords: PARTITION BY RANGE, generate_series(), DEFAULT partition
-- A NULL partition key can never satisfy a range bound, so NULLs go to the DEFAULT partition.
CREATE TABLE playground_18.shipments_by_month (shipment_id bigint, carrier text, shipped_at timestamptz)
    PARTITION BY RANGE (shipped_at);
DO $$
DECLARE m date;
BEGIN
    FOR m IN SELECT generate_series(date_trunc('month', min(shipped_at)), date_trunc('month', max(shipped_at)), interval '1 month')::date
             FROM logistics.shipments
    LOOP
        EXECUTE format('CREATE TABLE playground_18.%I PARTITION OF playground_18.shipments_by_month FOR VALUES FROM (%L) TO (%L)',
                       'shipments_' || to_char(m, 'YYYY_MM'), m, (m + interval '1 month')::date);
    END LOOP;
END $$;
CREATE TABLE playground_18.shipments_by_month_default PARTITION OF playground_18.shipments_by_month DEFAULT;
INSERT INTO playground_18.shipments_by_month SELECT shipment_id, carrier, shipped_at FROM logistics.shipments;
SELECT count(*) AS in_default_partition, count(*) FILTER (WHERE shipped_at IS NULL) AS with_null_key
FROM playground_18.shipments_by_month_default;
