-- =====================================================================
--  Chapter 18 · Exercises — partitioning
--  Work in schema playground_18 (CREATE SCHEMA IF NOT EXISTS playground_18;)
-- =====================================================================

-- [E18.01] (easy) How many partitions does analytics.events have, and how many of them are empty?

-- [E18.02] (easy) Show the EXPLAIN plan for counting 'purchase' events in the previous calendar month and
--          confirm only one partition is scanned.

-- [E18.03] (medium) Create playground_18.reviews_by_rating LIST-partitioned by rating with partitions for
--          (1,2) "negative", (3) "neutral", (4,5) "positive". Load catalog.reviews into it and count per partition.

-- [E18.04] (medium) Create playground_18.order_items_hash HASH-partitioned by order_id into 8 partitions, load
--          sales.order_items into it, and show the min/max rows per partition (how even is it?).

-- [E18.05] (hard) Create playground_18.shipments_by_month RANGE-partitioned by shipped_at with monthly partitions
--          generated dynamically for the full range of shipments.shipped_at, plus a DEFAULT partition for NULLs?
--          (Careful: can a NULL partition key go into a range partition?) Load the data and verify.
