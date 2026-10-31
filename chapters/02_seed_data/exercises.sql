-- =====================================================================
--  Chapter 02 · Exercises — INSERT, generate_series, COPY
--  Use schema playground_02 (CREATE SCHEMA IF NOT EXISTS playground_02;)
-- =====================================================================

-- [E02.01] (easy) Create playground_02.store_hours(day_name text, opens time, closes time) and fill
--          all 7 days in ONE INSERT statement (closed on Sunday: opens/closes NULL).

-- [E02.02] (easy) Using generate_series, list every date of the current month together with the
--          weekday name (hint: to_char(d, 'Day')).

-- [E02.03] (medium) Insert a new coupon 'WELCOMEBACK' (fixed ₹75, valid for the next 30 days) into
--          sales.coupons inside a transaction, return its coupon_id, then ROLLBACK.

-- [E02.04] (medium) Create playground_02.fake_reviews and generate 500 rows with: a random product_id
--          between 1 and 3000, a rating 1-5, and a created_at in the last 90 days. Make it reproducible.

-- [E02.05] (medium) Copy the 10 most recently registered users' email and created_at into
--          playground_02.recent_users using INSERT … SELECT (create the table first).

-- [E02.06] (medium) Export all warehouses to /tmp/warehouses.csv with a header, then load the file back
--          into a new table playground_02.warehouses_copy and compare the row counts.

-- [E02.07] (hard) Generate an hourly time grid for the last 24 hours and, for each hour, a
--          simulated number of site visitors that follows random_normal(500, 80), rounded.
