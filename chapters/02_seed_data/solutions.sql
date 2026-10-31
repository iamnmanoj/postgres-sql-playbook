-- =====================================================================
--  Chapter 02 · Solutions — INSERT, generate_series, COPY
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS playground_02;
DROP TABLE IF EXISTS playground_02.store_hours, playground_02.fake_reviews,
                     playground_02.recent_users, playground_02.warehouses_copy;

-- [E02.01] All seven days in one multi-row INSERT
-- Keywords: INSERT INTO, multi-row VALUES, NULL
CREATE TABLE playground_02.store_hours (day_name text PRIMARY KEY, opens time, closes time);
INSERT INTO playground_02.store_hours VALUES
    ('Monday', '09:00', '21:00'), ('Tuesday', '09:00', '21:00'), ('Wednesday', '09:00', '21:00'),
    ('Thursday', '09:00', '21:00'), ('Friday', '09:00', '22:00'), ('Saturday', '10:00', '22:00'),
    ('Sunday', NULL, NULL);
SELECT * FROM playground_02.store_hours;

-- [E02.02] Every date of the current month
-- Keywords: generate_series(), date_trunc(), to_char()
SELECT d::date AS day, trim(to_char(d, 'Day')) AS weekday
FROM generate_series(date_trunc('month', current_date),
                     date_trunc('month', current_date) + interval '1 month - 1 day',
                     interval '1 day') AS d;

-- [E02.03] Insert, inspect, undo
-- Keywords: BEGIN, INSERT, RETURNING, tstzrange(), ROLLBACK
BEGIN;
INSERT INTO sales.coupons (code, description, discount_type, discount_value, valid_during)
VALUES ('WELCOMEBACK', 'Win-back offer', 'fixed', 75, tstzrange(now(), now() + interval '30 days'))
RETURNING coupon_id, code, valid_during;
ROLLBACK;

-- [E02.04] Reproducible fake reviews
-- Keywords: setseed(), random(), generate_series(), INSERT … SELECT
CREATE TABLE playground_02.fake_reviews (product_id bigint, rating int, created_at timestamptz);
SELECT setseed(0.7);
INSERT INTO playground_02.fake_reviews
SELECT 1 + floor(random() * 3000)::int, 1 + floor(random() * 5)::int, now() - random() * interval '90 days'
FROM generate_series(1, 500);
SELECT rating, count(*) FROM playground_02.fake_reviews GROUP BY rating ORDER BY rating;

-- [E02.05] INSERT … SELECT with ORDER BY / LIMIT
-- Keywords: INSERT … SELECT, ORDER BY, LIMIT
CREATE TABLE playground_02.recent_users (email text, created_at timestamptz);
INSERT INTO playground_02.recent_users
SELECT email, created_at FROM core.users ORDER BY created_at DESC LIMIT 10;
SELECT * FROM playground_02.recent_users;

-- [E02.06] Round-trip through a CSV file
-- Keywords: COPY TO, COPY FROM, CREATE TABLE … (LIKE …)
COPY logistics.warehouses TO '/tmp/warehouses.csv' WITH (FORMAT csv, HEADER true);
CREATE TABLE playground_02.warehouses_copy (LIKE logistics.warehouses);
COPY playground_02.warehouses_copy FROM '/tmp/warehouses.csv' WITH (FORMAT csv, HEADER true);
SELECT (SELECT count(*) FROM logistics.warehouses) AS original,
       (SELECT count(*) FROM playground_02.warehouses_copy) AS copied;

-- [E02.07] Hourly grid with simulated visitors
-- Keywords: generate_series(), date_trunc(), random_normal(), round()
SELECT h AS hour_start, round(random_normal(500, 80)) AS visitors
FROM generate_series(date_trunc('hour', now()) - interval '23 hours', date_trunc('hour', now()), interval '1 hour') AS h;
