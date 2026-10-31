-- =====================================================================
--  Chapter 20 · Advanced extras
--  Ranges & multiranges, exclusion constraints, LISTEN/NOTIFY, sequences,
--  TABLESAMPLE, system catalogs, collations, row values, cursors, prepared
--  statements, psql power tools, crosstab, hstore, foreign data wrappers.
-- =====================================================================
DROP SCHEMA IF EXISTS playground_20 CASCADE;
CREATE SCHEMA playground_20;

-- =====================================================================
-- SECTION: Range & multirange types
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q20.01] Range basics: bounds, containment, overlap, adjacency
-- Keywords: daterange(), tstzrange(), int4range(), lower(), upper(), @>, &&, -|-, isempty(), [) bounds
-- Business question: Is today inside a coupon's validity? Do two payout periods touch?
-- ---------------------------------------------------------------------
SELECT code, valid_during,
       lower(valid_during)::date AS starts, upper(valid_during)::date AS ends,
       valid_during @> now()     AS valid_now,
       upper_inf(valid_during)   AS open_ended
FROM sales.coupons
WHERE code IN ('WELCOME10', 'OLDCODE', 'NEWYEAR30');
SELECT daterange('2025-01-01', '2025-02-01') && daterange('2025-01-31', '2025-03-01') AS overlaps,
       daterange('2025-01-01', '2025-02-01') -|- daterange('2025-02-01', '2025-03-01') AS adjacent,
       int4range(10, 20) * int4range(15, 30)                                       AS intersection,
       isempty(int4range(5, 5))                                                    AS empty_range,
       int4range(1, 10, '[]')                                                      AS inclusive_canonicalised;

-- ---------------------------------------------------------------------
-- [Q20.02] Aggregate ranges into multiranges and find GAPS
-- Keywords: range_agg(), multirange, datemultirange(), - (difference), unnest(multirange)
-- Business question: Which months in the last year did our least-active seller NOT receive a payout?
-- ---------------------------------------------------------------------
WITH seller AS (
    SELECT seller_id FROM core.seller_payouts GROUP BY seller_id ORDER BY count(*), seller_id LIMIT 1
), covered AS (
    SELECT range_agg(period) AS paid_periods FROM core.seller_payouts WHERE seller_id = (SELECT seller_id FROM seller)
), wanted AS (
    SELECT datemultirange(daterange((date_trunc('month', now()) - interval '12 months')::date,
                                    date_trunc('month', now())::date)) AS last_year
)
SELECT (SELECT seller_id FROM seller) AS seller_id, covered.paid_periods, gap AS months_without_payout
FROM covered, wanted, unnest(wanted.last_year - covered.paid_periods) AS gap;

-- ---------------------------------------------------------------------
-- [Q20.03] Intersect many ranges
-- Keywords: range_intersect_agg()
-- Business question: When were ALL of the PRIME15, WELCOME10 and the current monthly coupon valid at once?
-- ---------------------------------------------------------------------
SELECT range_intersect_agg(valid_during) AS common_window
FROM sales.coupons
WHERE code IN ('PRIME15', 'WELCOME10', 'MONTHLY' || upper(to_char(now(), 'MONYY')));

-- ---------------------------------------------------------------------
-- [Q20.04] EXCLUDE constraints in action
-- Keywords: EXCLUDE USING gist, exclusion_violation, btree_gist
-- Business question: Try to book a second, overlapping payout for a seller.
-- ---------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO core.seller_payouts (seller_id, period, gross_sales, commission)
    SELECT seller_id, daterange(lower(period) + 10, upper(period) + 10), 1, 0
    FROM core.seller_payouts ORDER BY payout_id LIMIT 1;
EXCEPTION WHEN exclusion_violation THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;
CREATE TABLE playground_20.room_bookings (                 -- the classic: no double-booking
    room   text,
    during tstzrange,
    EXCLUDE USING gist (room WITH =, during WITH &&)
);
INSERT INTO playground_20.room_bookings VALUES ('photo-studio', tstzrange(now(), now() + interval '2 hours'));

-- =====================================================================
-- SECTION: Asynchronous messaging
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q20.05] Publish/subscribe inside the database
-- Keywords: LISTEN, NOTIFY, pg_notify(), UNLISTEN
-- Business question: Tell the warehouse service instantly when an order is paid.
-- Note: psql prints 'Asynchronous notification … received' after the next command. Notifications are sent at COMMIT.
-- ---------------------------------------------------------------------
LISTEN order_paid;
NOTIFY order_paid, 'order 42';
SELECT pg_notify('order_paid', json_build_object('order_id', 43, 'amount', 999)::text);
SELECT 'check the notifications printed above' AS hint;
UNLISTEN order_paid;

-- =====================================================================
-- SECTION: Sequences in depth
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q20.06] Sequence options and identity internals
-- Keywords: CREATE SEQUENCE … CACHE, CYCLE, MINVALUE, MAXVALUE, OWNED BY, pg_get_serial_sequence(), pg_sequences, ALTER … RESTART
-- ---------------------------------------------------------------------
CREATE SEQUENCE playground_20.locker_no MINVALUE 1 MAXVALUE 3 CYCLE CACHE 1;
SELECT nextval('playground_20.locker_no') FROM generate_series(1, 5);     -- 1,2,3,1,2 (wraps around)
SELECT pg_get_serial_sequence('sales.orders', 'order_id') AS identity_sequence;
SELECT schemaname, sequencename, last_value, increment_by, cache_size FROM pg_sequences WHERE schemaname = 'sales' LIMIT 3;
ALTER SEQUENCE playground_20.locker_no RESTART WITH 2;
SELECT nextval('playground_20.locker_no') AS after_restart;

-- =====================================================================
-- SECTION: Sampling
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q20.07] Random samples of big tables, fast
-- Keywords: TABLESAMPLE SYSTEM, TABLESAMPLE BERNOULLI, REPEATABLE
-- Business question: Estimate average order value from a 1% sample.
-- Note: SYSTEM samples whole pages (fast, clumpy); BERNOULLI samples rows (slower, uniform).
-- ---------------------------------------------------------------------
SELECT 'system'    AS method, count(*) AS sampled, round(avg(grand_total)) AS est_aov FROM sales.orders TABLESAMPLE SYSTEM (1) REPEATABLE (42)
UNION ALL
SELECT 'bernoulli', count(*), round(avg(grand_total)) FROM sales.orders TABLESAMPLE BERNOULLI (1) REPEATABLE (42)
UNION ALL
SELECT 'exact', count(*), round(avg(grand_total)) FROM sales.orders;

-- =====================================================================
-- SECTION: The system catalogs
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q20.08] Tables, columns and their types straight from pg_catalog
-- Keywords: pg_class, pg_attribute, pg_namespace, format_type(), relkind
-- ---------------------------------------------------------------------
SELECT n.nspname AS schema, c.relname AS table_name, c.relkind, c.reltuples::bigint AS est_rows
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'sales' AND c.relkind IN ('r', 'p', 'v', 'm')
ORDER BY c.relname;
SELECT a.attnum, a.attname, format_type(a.atttypid, a.atttypmod) AS data_type, a.attnotnull, a.attgenerated
FROM pg_attribute a
WHERE a.attrelid = 'sales.order_items'::regclass AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY a.attnum;

-- ---------------------------------------------------------------------
-- [Q20.09] Constraints and foreign-key graph
-- Keywords: pg_constraint, contype, pg_get_constraintdef(), information_schema.table_constraints, key_column_usage
-- Business question: Draw the FK graph (child → parent) of the sales schema.
-- ---------------------------------------------------------------------
SELECT conrelid::regclass AS child, confrelid::regclass AS parent, conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE contype = 'f' AND connamespace = 'sales'::regnamespace
ORDER BY 1, 2
LIMIT 8;
SELECT tc.constraint_type, count(*)
FROM information_schema.table_constraints tc
WHERE tc.table_schema IN ('core', 'catalog', 'logistics', 'sales')
GROUP BY tc.constraint_type
ORDER BY 2 DESC;

-- ---------------------------------------------------------------------
-- [Q20.10] What depends on what?
-- Keywords: pg_depend, pg_describe_object(), deptype
-- Business question: Which objects would break if the sales.order_status type were dropped?
-- ---------------------------------------------------------------------
SELECT DISTINCT pg_describe_object(classid, objid, objsubid) AS dependent_object, deptype
FROM pg_depend
WHERE refobjid = 'sales.order_status'::regtype
ORDER BY 1
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q20.11] Server settings and extensions
-- Keywords: pg_settings, current_setting(), pg_extension, pg_available_extensions, SHOW ALL
-- ---------------------------------------------------------------------
SELECT name, setting, unit, context FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'max_connections', 'wal_level', 'timezone');
SELECT extname, extversion FROM pg_extension ORDER BY extname;
SELECT count(*) AS extensions_available FROM pg_available_extensions;

-- =====================================================================
-- SECTION: Collations
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q20.12] Language-aware sorting and case-insensitive collations
-- Keywords: COLLATE, CREATE COLLATION, ICU, deterministic = false
-- Business question: Sort names naturally ("item 2" before "item 10") and compare case-insensitively.
-- ---------------------------------------------------------------------
CREATE COLLATION IF NOT EXISTS playground_20.natural_sort (provider = icu, locale = 'en-u-kn');
CREATE COLLATION IF NOT EXISTS playground_20.ci (provider = icu, locale = 'und-u-ks-level2', deterministic = false);
SELECT name FROM (VALUES ('item 10'), ('item 2'), ('Item 1')) t(name) ORDER BY name COLLATE "C";
SELECT name FROM (VALUES ('item 10'), ('item 2'), ('Item 1')) t(name) ORDER BY name COLLATE playground_20.natural_sort;
SELECT 'SAVE20' = 'save20' COLLATE playground_20.ci AS equal_ignoring_case;

-- =====================================================================
-- SECTION: Row values & composite types
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q20.13] Whole rows as values
-- Keywords: row value t.*, ROW(), (composite).field, record comparison, row_to_json()
-- Business question: Detect if a product row changed between two snapshots by comparing whole rows.
-- ---------------------------------------------------------------------
CREATE TABLE playground_20.brands_snapshot AS SELECT * FROM catalog.brands;
UPDATE playground_20.brands_snapshot SET founded_year = founded_year + 1 WHERE brand_id = 3;
SELECT b.brand_id, b.name
FROM catalog.brands b JOIN playground_20.brands_snapshot s USING (brand_id)
WHERE (b.*) IS DISTINCT FROM (s.*);                              -- compares every column at once
SELECT ROW(1, 'x', now()::date) AS anonymous_row, (w).code AS field_of_row
FROM (SELECT w FROM logistics.warehouses w LIMIT 1) t;

-- =====================================================================
-- SECTION: Cursors & prepared statements
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q20.14] Server-side cursors in plain SQL
-- Keywords: DECLARE CURSOR, FETCH, MOVE, CLOSE, WITH HOLD, SCROLL
-- Business question: Stream a big export in chunks without loading it all in memory.
-- ---------------------------------------------------------------------
BEGIN;
DECLARE big_orders SCROLL CURSOR FOR SELECT order_number, grand_total FROM sales.orders ORDER BY grand_total DESC;
FETCH 3 FROM big_orders;                 -- rows 1-3
MOVE FORWARD 100 IN big_orders;          -- skip
FETCH 2 FROM big_orders;                 -- rows 104-105
FETCH PRIOR FROM big_orders;             -- scroll back
CLOSE big_orders;
COMMIT;

-- ---------------------------------------------------------------------
-- [Q20.15] Parse/plan once, execute many times
-- Keywords: PREPARE, EXECUTE, DEALLOCATE, pg_prepared_statements
-- Note: Drivers do this automatically with parameterised queries ($1) — also the best defence against SQL injection.
-- ---------------------------------------------------------------------
PREPARE user_orders(bigint, int) AS
    SELECT order_number, status, grand_total FROM sales.orders WHERE user_id = $1 ORDER BY placed_at DESC LIMIT $2;
EXECUTE user_orders(42, 3);
EXECUTE user_orders(7, 2);
SELECT name, parameter_types, generic_plans, custom_plans FROM pg_prepared_statements;
DEALLOCATE user_orders;

-- =====================================================================
-- SECTION: psql power tools
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q20.16] Store results in variables, generate & run SQL, pivot output
-- Keywords: \gset, :'var', \gexec, \crosstabview
-- ---------------------------------------------------------------------
SELECT max(placed_at)::date AS last_day, count(*) AS total_orders FROM sales.orders \gset
SELECT :'last_day' AS last_order_day, :total_orders AS orders;
-- \gexec runs every cell of the result as a new SQL statement (here: ANALYZE each playground_20 table)
SELECT format('ANALYZE %I.%I', schemaname, tablename) FROM pg_tables WHERE schemaname = 'playground_20' \gexec
-- \crosstabview pivots a 3-column result in psql: rows × columns → values
SELECT metadata ->> 'channel' AS channel, status, count(*)
FROM sales.orders WHERE status IN ('delivered', 'cancelled', 'refunded')
GROUP BY 1, 2 ORDER BY 1, 2 \crosstabview

-- ---------------------------------------------------------------------
-- [Q20.17] Pivot in SQL with the tablefunc extension
-- Keywords: tablefunc, crosstab()
-- Business question: Orders per payment method (columns) per quarter (rows).
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS tablefunc;
SELECT *
FROM crosstab(
    $$ SELECT to_char(date_trunc('quarter', created_at), 'YYYY-"Q"Q'), method::text, count(*)
       FROM sales.payments WHERE status = 'captured' GROUP BY 1, 2 ORDER BY 1, 2 $$,
    $$ VALUES ('card'), ('upi'), ('wallet'), ('netbanking'), ('cod') $$
) AS pivot(quarter text, card bigint, upi bigint, wallet bigint, netbanking bigint, cod bigint)
ORDER BY quarter DESC
LIMIT 4;

-- =====================================================================
-- SECTION: More extensions
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q20.18] hstore: the original key/value type
-- Keywords: hstore, ->, ?, akeys(), hstore_to_jsonb()
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS hstore;
SELECT h -> 'color' AS color, h ? 'size' AS has_size, akeys(h) AS keys, hstore_to_jsonb(h) AS as_jsonb
FROM (SELECT 'color => red, size => XL'::hstore AS h) t;

-- ---------------------------------------------------------------------
-- [Q20.19] Query another PostgreSQL database as if it were local
-- Keywords: postgres_fdw, CREATE SERVER, CREATE USER MAPPING, IMPORT FOREIGN SCHEMA, foreign table
-- Business question: Reporting DB reads warehouses from the "operational" DB (here: a loopback to ourselves).
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
DROP SERVER IF EXISTS loopback CASCADE;
DO $$ BEGIN
    EXECUTE format('CREATE SERVER loopback FOREIGN DATA WRAPPER postgres_fdw OPTIONS (dbname %L)', current_database());
END $$;
CREATE USER MAPPING FOR CURRENT_USER SERVER loopback OPTIONS (user 'postgres');
IMPORT FOREIGN SCHEMA logistics LIMIT TO (warehouses) FROM SERVER loopback INTO playground_20;
SELECT code, city FROM playground_20.warehouses ORDER BY code LIMIT 3;     -- fetched over a connection
EXPLAIN (VERBOSE, COSTS OFF) SELECT code FROM playground_20.warehouses WHERE capacity > 100000;   -- WHERE pushed down

-- ---------------------------------------------------------------------
-- [Q20.20] Server information one-liners
-- Keywords: pg_postmaster_start_time(), inet_server_port(), server_version_num
-- ---------------------------------------------------------------------
SELECT pg_postmaster_start_time() AS server_started, now() - pg_postmaster_start_time() AS uptime,
       inet_server_port() AS port, current_setting('server_version_num') AS version_num;
