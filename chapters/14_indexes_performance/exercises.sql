-- =====================================================================
--  Chapter 14 · Exercises — indexes & performance
--  Name your indexes ex14_* so they're easy to find and drop.
-- =====================================================================

-- [E14.01] (easy) Show the plan for "all shipments of carrier 'DTDC' that are 'lost'". Then create the best
--          index for it and show the new plan.

-- [E14.02] (easy) What is the total size (table + indexes) of sales.order_items? And just its indexes?

-- [E14.03] (medium) The notifications screen runs: unread notifications for a user, newest first, LIMIT 20.
--          Create a small partial index that this query can use, and prove it with EXPLAIN.

-- [E14.04] (medium) Add an index that supports looking up products by attributes->>'isbn' with = and show it is used.

-- [E14.05] (medium) Rewrite this non-sargable query so it can use an index on orders(placed_at), and compare
--          plans:  SELECT count(*) FROM sales.orders WHERE extract(year FROM placed_at) = extract(year FROM now());

-- [E14.06] (hard) Using EXPLAIN (ANALYZE, BUFFERS), compare "count events per type in the last 7 days" on
--          analytics.events with and without a BRIN index on occurred_at. Explain the difference.

-- [E14.07] (hard) List the 5 largest indexes in the app schemas with their table and how often they were used.
--          Which of them would you consider dropping, and why might idx_scan = 0 be misleading?
