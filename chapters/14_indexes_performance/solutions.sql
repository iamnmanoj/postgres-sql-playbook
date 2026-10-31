-- =====================================================================
--  Chapter 14 · Solutions — indexes & performance
-- =====================================================================

-- [E14.01] Lost DTDC shipments
-- Keywords: EXPLAIN, composite index
DROP INDEX IF EXISTS logistics.ex14_shipments_carrier_status;
EXPLAIN (COSTS OFF) SELECT * FROM logistics.shipments WHERE carrier = 'DTDC' AND status = 'lost';
CREATE INDEX ex14_shipments_carrier_status ON logistics.shipments (carrier, status);
ANALYZE logistics.shipments;
EXPLAIN (COSTS OFF) SELECT * FROM logistics.shipments WHERE carrier = 'DTDC' AND status = 'lost';

-- [E14.02] Table sizes
-- Keywords: pg_total_relation_size(), pg_indexes_size(), pg_size_pretty()
SELECT pg_size_pretty(pg_total_relation_size('sales.order_items')) AS total,
       pg_size_pretty(pg_indexes_size('sales.order_items'))        AS indexes_only;

-- [E14.03] Partial index for unread notifications
-- Keywords: partial index, ORDER BY … DESC, LIMIT
CREATE INDEX IF NOT EXISTS ex14_notifications_unread ON core.notifications (user_id, sent_at DESC) WHERE read_at IS NULL;
ANALYZE core.notifications;
EXPLAIN (COSTS OFF)
SELECT notification_id, template, sent_at FROM core.notifications
WHERE user_id = 8 AND read_at IS NULL
ORDER BY sent_at DESC LIMIT 20;
-- The planner may still pick Bitmap Scan + Sort: for a handful of rows sorting is cheaper than an ordered
-- index scan. With thousands of unread rows per user it switches to an Index Scan without a Sort node.

-- [E14.04] Expression index on a JSONB field
-- Keywords: expression index, ->>
CREATE INDEX IF NOT EXISTS ex14_products_isbn ON catalog.products ((attributes ->> 'isbn'));
ANALYZE catalog.products;
EXPLAIN (COSTS OFF) SELECT name FROM catalog.products WHERE attributes ->> 'isbn' = '9780014570960';

-- [E14.05] Sargable rewrite
-- Keywords: date_trunc(), range predicate
EXPLAIN (COSTS OFF) SELECT count(*) FROM sales.orders WHERE extract(year FROM placed_at) = extract(year FROM now());
EXPLAIN (COSTS OFF) SELECT count(*) FROM sales.orders
WHERE placed_at >= date_trunc('year', now()) AND placed_at < date_trunc('year', now()) + interval '1 year';

-- [E14.06] BRIN on a partitioned table (index is created on every partition)
-- Keywords: BRIN, EXPLAIN (ANALYZE, BUFFERS), partition pruning
DROP INDEX IF EXISTS analytics.ex14_events_brin;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT event_type, count(*) FROM analytics.events WHERE occurred_at >= now() - interval '7 days' GROUP BY 1;
CREATE INDEX ex14_events_brin ON analytics.events USING brin (occurred_at);
ANALYZE analytics.events;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT event_type, count(*) FROM analytics.events WHERE occurred_at >= now() - interval '7 days' GROUP BY 1;
-- Partition pruning already limits the scan to 1-2 monthly partitions; BRIN then skips block ranges inside
-- them. On this small data set the gain is modest; on billions of rows it is dramatic, at a tiny index size.
DROP INDEX analytics.ex14_events_brin;

-- [E14.07] Largest indexes and their usage
-- Keywords: pg_stat_user_indexes, pg_relation_size()
SELECT indexrelid::regclass AS index_name, relid::regclass AS table_name, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname IN ('core', 'catalog', 'logistics', 'sales')
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 5;
-- idx_scan counts since the last stats reset and on THIS server only: an index unused here may serve a
-- monthly report, a replica's workload, or enforce a UNIQUE/PRIMARY KEY constraint (never drop those).
