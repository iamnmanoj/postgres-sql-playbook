-- =====================================================================
--  Chapter 10 · Changing data: UPDATE, DELETE, UPSERT, MERGE, TRUNCATE
--  Every change to ShopSphere tables is wrapped in BEGIN … ROLLBACK.
--  Sandbox tables live in playground_10.
-- =====================================================================
DROP SCHEMA IF EXISTS playground_10 CASCADE;
CREATE SCHEMA playground_10;

-- =====================================================================
-- SECTION: UPDATE
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q10.01] Update one column for matching rows
-- Keywords: UPDATE, SET, WHERE
-- Business question: Suspend a user account.
-- ---------------------------------------------------------------------
BEGIN;
UPDATE core.users SET status = 'suspended', updated_at = now() WHERE user_id = 42;
SELECT user_id, status FROM core.users WHERE user_id = 42;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.02] Update using an expression of the current value + see the result
-- Keywords: UPDATE … SET col = col * x, RETURNING
-- Business question: A 10% price increase for one brand; return the new prices.
-- ---------------------------------------------------------------------
BEGIN;
WITH changed AS (
    UPDATE catalog.products
    SET base_price = round(base_price * 1.10, 2) - 0.01,
        updated_at = now()
    WHERE brand_id = (SELECT brand_id FROM catalog.brands WHERE name = 'Sonique')
    RETURNING product_id, name, base_price AS new_price
)
SELECT * FROM changed ORDER BY new_price DESC LIMIT 5;   -- RETURNING rows can be post-processed via a CTE
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.03] UPDATE … FROM: update using values from another table (join)
-- Keywords: UPDATE … FROM
-- Business question: Recompute every seller's rating_avg from current reviews.
-- ---------------------------------------------------------------------
BEGIN;
UPDATE core.sellers s
SET rating_avg = r.avg_rating
FROM (SELECT p.seller_id, round(avg(rv.rating), 2) AS avg_rating
      FROM catalog.reviews rv JOIN catalog.products p USING (product_id)
      GROUP BY p.seller_id) r
WHERE r.seller_id = s.seller_id
  AND s.rating_avg IS DISTINCT FROM r.avg_rating;     -- only touch rows that actually change
SELECT count(*) AS sellers_with_rating FROM core.sellers WHERE rating_avg IS NOT NULL;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.04] Update several columns from a subquery at once
-- Keywords: UPDATE … SET (a, b) = (SELECT …)
-- Business question: Refresh an order's subtotal and tax from its items.
-- ---------------------------------------------------------------------
BEGIN;
UPDATE sales.orders o
SET (subtotal, tax_total) = (SELECT sum(oi.line_total), round(sum(oi.line_total) * 0.05, 2)
                             FROM sales.order_items oi WHERE oi.order_id = o.order_id)
WHERE o.order_id = 100
RETURNING order_id, subtotal, tax_total, grand_total;     -- grand_total recalculated automatically
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.05] Conditional update with CASE
-- Keywords: UPDATE … SET col = CASE …
-- Business question: Re-tier reorder levels based on stock in one pass.
-- ---------------------------------------------------------------------
BEGIN;
UPDATE logistics.inventory
SET reorder_level = CASE WHEN quantity_on_hand = 0   THEN 50
                         WHEN quantity_on_hand < 50  THEN 30
                         ELSE reorder_level END
WHERE warehouse_id = 1;
SELECT reorder_level, count(*) FROM logistics.inventory WHERE warehouse_id = 1 GROUP BY 1 ORDER BY 1;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.06] JSONB and array columns can be updated in place
-- Keywords: UPDATE with jsonb_set(), array_append(), ||
-- Business question: Turn on dark mode for user 7 and tag product 1 as 'trending'.
-- ---------------------------------------------------------------------
BEGIN;
UPDATE core.users SET preferences = jsonb_set(preferences, '{theme}', '"dark"') WHERE user_id = 7
RETURNING preferences;
UPDATE catalog.products SET tags = array_append(tags, 'trending') WHERE product_id = 1 AND NOT ('trending' = ANY (tags))
RETURNING tags;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.07] Generated columns can't be written
-- Keywords: GENERATED column, cannot assign, DEFAULT
-- ---------------------------------------------------------------------
DO $$
BEGIN
    UPDATE sales.orders SET grand_total = 0 WHERE order_id = 1;
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

-- =====================================================================
-- SECTION: DELETE
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q10.08] Delete matching rows and return what was removed
-- Keywords: DELETE FROM, WHERE, RETURNING
-- Business question: Clear cart items added more than 60 days ago.
-- ---------------------------------------------------------------------
BEGIN;
WITH removed AS (
    DELETE FROM sales.cart_items WHERE added_at < now() - interval '60 days'
    RETURNING cart_id, variant_id
)
SELECT count(*) AS removed_items, count(DISTINCT cart_id) AS carts_affected FROM removed;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.09] DELETE … USING: delete based on a join
-- Keywords: DELETE … USING
-- Business question: Remove wishlist entries for products that are no longer active.
-- ---------------------------------------------------------------------
BEGIN;
DELETE FROM sales.wishlists w
USING catalog.products p
WHERE p.product_id = w.product_id
  AND NOT p.is_active;
SELECT count(*) AS remaining_inactive_wishes
FROM sales.wishlists w JOIN catalog.products p USING (product_id) WHERE NOT p.is_active;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.10] Delete with a subquery / NOT EXISTS
-- Keywords: DELETE … WHERE NOT EXISTS
-- Business question: Delete empty carts (no items).
-- ---------------------------------------------------------------------
BEGIN;
DELETE FROM sales.carts c
WHERE NOT EXISTS (SELECT 1 FROM sales.cart_items ci WHERE ci.cart_id = c.cart_id);   -- psql prints "DELETE n"
SELECT count(*) AS empty_carts_left FROM sales.carts c
WHERE NOT EXISTS (SELECT 1 FROM sales.cart_items ci WHERE ci.cart_id = c.cart_id);
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.11] Batched deletes (keep transactions and locks short on big tables)
-- Keywords: DELETE … WHERE ctid IN (SELECT … LIMIT), ctid
-- Business question: Purge old click-stream events 1,000 rows at a time.
-- Note: Run in a loop from the app/cron until it deletes 0 rows. (Dropping partitions is even better: ch18.)
-- ---------------------------------------------------------------------
BEGIN;
DELETE FROM analytics.events
WHERE (event_id, occurred_at) IN (
    SELECT event_id, occurred_at FROM analytics.events
    WHERE occurred_at < now() - interval '330 days'
    ORDER BY occurred_at
    LIMIT 1000);
CREATE TEMP TABLE batch_demo AS SELECT generate_series(1, 5000) AS n;
DELETE FROM batch_demo WHERE ctid IN (SELECT ctid FROM batch_demo LIMIT 1000);   -- ctid = physical row id
SELECT count(*) AS left_after_one_batch FROM batch_demo;
ROLLBACK;

-- =====================================================================
-- SECTION: UPSERT — INSERT … ON CONFLICT
-- =====================================================================
CREATE TABLE playground_10.daily_product_views (
    product_id bigint NOT NULL,
    day        date   NOT NULL,
    views      int    NOT NULL DEFAULT 0,
    last_seen  timestamptz,
    PRIMARY KEY (product_id, day)
);

-- ---------------------------------------------------------------------
-- [Q10.12] Ignore duplicates
-- Keywords: ON CONFLICT DO NOTHING
-- Business question: Add to wishlist — if it's already there, do nothing.
-- ---------------------------------------------------------------------
BEGIN;
INSERT INTO sales.wishlists (user_id, product_id)
SELECT user_id, product_id FROM sales.wishlists LIMIT 1          -- guaranteed duplicate
ON CONFLICT DO NOTHING
RETURNING *;                                                     -- returns nothing: row skipped
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.13] Insert or update (the classic upsert)
-- Keywords: ON CONFLICT (cols) DO UPDATE, EXCLUDED
-- Business question: Count product views per day: first view inserts, later views increment.
-- Note: EXCLUDED is the row that was proposed for insertion.
-- ---------------------------------------------------------------------
INSERT INTO playground_10.daily_product_views AS d (product_id, day, views, last_seen)
VALUES (1, current_date, 1, now())
ON CONFLICT (product_id, day)
DO UPDATE SET views = d.views + EXCLUDED.views,
              last_seen = EXCLUDED.last_seen;
INSERT INTO playground_10.daily_product_views AS d (product_id, day, views, last_seen)
VALUES (1, current_date, 1, now())
ON CONFLICT (product_id, day)
DO UPDATE SET views = d.views + EXCLUDED.views, last_seen = EXCLUDED.last_seen
RETURNING *, (xmax = 0) AS was_inserted;                 -- trick: xmax = 0 → inserted, else updated

-- ---------------------------------------------------------------------
-- [Q10.14] Bulk upsert from a query
-- Keywords: INSERT … SELECT … ON CONFLICT DO UPDATE
-- Business question: Aggregate yesterday's product_view events into the daily table (re-runnable job).
-- ---------------------------------------------------------------------
INSERT INTO playground_10.daily_product_views AS d (product_id, day, views, last_seen)
SELECT product_id, occurred_at::date, count(*), max(occurred_at)
FROM analytics.events
WHERE event_type = 'product_view' AND occurred_at >= current_date - 7 AND occurred_at < current_date
GROUP BY product_id, occurred_at::date
ON CONFLICT (product_id, day)
DO UPDATE SET views = EXCLUDED.views, last_seen = EXCLUDED.last_seen;     -- idempotent: overwrite, not add
SELECT count(*) AS rows_in_daily_table, sum(views) AS total_views FROM playground_10.daily_product_views;

-- ---------------------------------------------------------------------
-- [Q10.15] Conflict on a named constraint, and update only when something changed
-- Keywords: ON CONFLICT ON CONSTRAINT, DO UPDATE … WHERE
-- Business question: Sync a brand list from a partner feed without touching unchanged rows.
-- ---------------------------------------------------------------------
BEGIN;
INSERT INTO catalog.brands AS b (name, country_code, founded_year)
VALUES ('Voltix', 'IN', 2012),          -- unchanged → skipped by WHERE
       ('Auralux', 'US', 2005),         -- changed founded_year → updated
       ('Brand New Co', 'IN', 2025)     -- new → inserted
ON CONFLICT ON CONSTRAINT brands_name_key
DO UPDATE SET country_code = EXCLUDED.country_code, founded_year = EXCLUDED.founded_year
WHERE (b.country_code, b.founded_year) IS DISTINCT FROM (EXCLUDED.country_code, EXCLUDED.founded_year)
RETURNING name, founded_year, (xmax = 0) AS inserted;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.16] Upsert into a table whose unique key is a PARTIAL index
-- Keywords: ON CONFLICT (col) WHERE predicate (index inference)
-- Business question: Set a user's default address (only one default allowed per user).
-- ---------------------------------------------------------------------
BEGIN;
UPDATE core.addresses SET is_default = false WHERE user_id = 10 AND is_default;
INSERT INTO core.addresses (user_id, line1, city, state, postal_code, is_default)
VALUES (10, '9 Residency Road', 'Bengaluru', 'Karnataka', '560025', true)
ON CONFLICT (user_id) WHERE is_default DO NOTHING
RETURNING address_id, is_default;
ROLLBACK;

-- =====================================================================
-- SECTION: MERGE (SQL standard, PG15+; RETURNING & NOT MATCHED BY SOURCE in PG17)
-- =====================================================================
CREATE TABLE playground_10.stock_feed (variant_id bigint, warehouse_id smallint, qty int);
INSERT INTO playground_10.stock_feed
SELECT variant_id, warehouse_id, quantity_on_hand + 5 FROM logistics.inventory WHERE warehouse_id = 2 LIMIT 3;   -- changed
INSERT INTO playground_10.stock_feed
SELECT variant_id, 2, 0 FROM logistics.inventory WHERE warehouse_id = 2 OFFSET 3 LIMIT 1;                         -- now zero
INSERT INTO playground_10.stock_feed
SELECT v.variant_id, 2, 40 FROM catalog.product_variants v
WHERE NOT EXISTS (SELECT 1 FROM logistics.inventory i WHERE i.variant_id = v.variant_id AND i.warehouse_id = 2) LIMIT 2;  -- new

-- ---------------------------------------------------------------------
-- [Q10.17] One statement that inserts, updates and deletes based on a source
-- Keywords: MERGE INTO … USING … ON, WHEN MATCHED, WHEN NOT MATCHED, THEN UPDATE/INSERT/DELETE
-- Business question: Apply a warehouse stock feed: update counts, delete zero rows, insert new items.
-- ---------------------------------------------------------------------
BEGIN;
MERGE INTO logistics.inventory AS i
USING playground_10.stock_feed AS f
   ON i.variant_id = f.variant_id AND i.warehouse_id = f.warehouse_id
WHEN MATCHED AND f.qty = 0 AND i.quantity_reserved = 0 THEN
    DELETE
WHEN MATCHED THEN
    UPDATE SET quantity_on_hand = greatest(f.qty, i.quantity_reserved), updated_at = now()   -- respect CHECK reserved <= on_hand
WHEN NOT MATCHED THEN
    INSERT (variant_id, warehouse_id, quantity_on_hand) VALUES (f.variant_id, f.warehouse_id, f.qty);
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.18] See what MERGE did to each row
-- Keywords: MERGE … RETURNING, merge_action()
-- ---------------------------------------------------------------------
BEGIN;
MERGE INTO logistics.inventory AS i
USING playground_10.stock_feed AS f
   ON i.variant_id = f.variant_id AND i.warehouse_id = f.warehouse_id
WHEN MATCHED AND f.qty = 0 AND i.quantity_reserved = 0 THEN DELETE
WHEN MATCHED THEN UPDATE SET quantity_on_hand = greatest(f.qty, i.quantity_reserved)
WHEN NOT MATCHED THEN INSERT (variant_id, warehouse_id, quantity_on_hand) VALUES (f.variant_id, f.warehouse_id, f.qty)
RETURNING merge_action() AS action, f.variant_id, f.qty;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q10.19] Handle target rows that are missing from the source
-- Keywords: WHEN NOT MATCHED BY SOURCE, DO NOTHING
-- Business question: Full sync of a small table: rows not in the feed are deleted.
-- ---------------------------------------------------------------------
CREATE TABLE playground_10.carriers (code text PRIMARY KEY, name text, active boolean DEFAULT true);
INSERT INTO playground_10.carriers VALUES ('BD', 'BlueDart'), ('DL', 'Delhivery'), ('OLD', 'Retired Couriers');
MERGE INTO playground_10.carriers AS t
USING (VALUES ('BD', 'BlueDart Express'), ('DL', 'Delhivery'), ('XB', 'XpressBees')) AS s(code, name)
   ON t.code = s.code
WHEN MATCHED AND t.name <> s.name THEN UPDATE SET name = s.name
WHEN MATCHED THEN DO NOTHING
WHEN NOT MATCHED BY TARGET THEN INSERT (code, name) VALUES (s.code, s.name)
WHEN NOT MATCHED BY SOURCE THEN DELETE
RETURNING merge_action(), t.*;

-- =====================================================================
-- SECTION: TRUNCATE
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q10.20] Empty tables instantly
-- Keywords: TRUNCATE, RESTART IDENTITY, CASCADE
-- Note: TRUNCATE doesn't scan rows (very fast), resets identity with RESTART IDENTITY,
--       and CASCADE also truncates tables that reference it via foreign keys. It IS transactional in PostgreSQL.
-- ---------------------------------------------------------------------
CREATE TABLE playground_10.import_batches (batch_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY, file text);
CREATE TABLE playground_10.import_rows (batch_id int REFERENCES playground_10.import_batches, payload text);
INSERT INTO playground_10.import_batches (file) VALUES ('a.csv'), ('b.csv');
INSERT INTO playground_10.import_rows VALUES (1, 'x'), (2, 'y');
TRUNCATE playground_10.import_batches RESTART IDENTITY CASCADE;
INSERT INTO playground_10.import_batches (file) VALUES ('c.csv') RETURNING batch_id;   -- back to 1
SELECT count(*) AS rows_left FROM playground_10.import_rows;
