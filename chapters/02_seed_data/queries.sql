-- =====================================================================
--  Chapter 02 · Getting data in: INSERT, generate_series, COPY
--  Demo tables live in playground_02; changes to real tables are rolled back.
-- =====================================================================
DROP SCHEMA IF EXISTS playground_02 CASCADE;
CREATE SCHEMA playground_02;

CREATE TABLE playground_02.newsletter (
    id         int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email      text NOT NULL UNIQUE,
    city       text DEFAULT 'Bengaluru',
    joined_at  timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================
-- SECTION: INSERT basics
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q02.01] Insert one row, naming the columns
-- Keywords: INSERT INTO, VALUES
-- Business question: A visitor subscribes to the newsletter.
-- Note: Always list columns; the statement keeps working if columns are added later.
-- ---------------------------------------------------------------------
INSERT INTO playground_02.newsletter (email, city) VALUES ('arjun@example.com', 'Pune');

-- ---------------------------------------------------------------------
-- [Q02.02] Let defaults fill in missing columns, explicitly or implicitly
-- Keywords: DEFAULT (keyword), omitted columns
-- ---------------------------------------------------------------------
INSERT INTO playground_02.newsletter (email) VALUES ('diya@example.com');                    -- city & joined_at default
INSERT INTO playground_02.newsletter (email, city) VALUES ('kabir@example.com', DEFAULT);    -- DEFAULT keyword

-- ---------------------------------------------------------------------
-- [Q02.03] A row made only of defaults
-- Keywords: DEFAULT VALUES
-- Business question: Open a new (empty) support-chat session row.
-- ---------------------------------------------------------------------
CREATE TABLE playground_02.chat_sessions (
    session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    started_at timestamptz NOT NULL DEFAULT now(),
    channel    text NOT NULL DEFAULT 'web'
);
INSERT INTO playground_02.chat_sessions DEFAULT VALUES;
SELECT * FROM playground_02.chat_sessions;

-- ---------------------------------------------------------------------
-- [Q02.04] Several rows in one statement (faster than many single INSERTs)
-- Keywords: multi-row VALUES
-- ---------------------------------------------------------------------
INSERT INTO playground_02.newsletter (email, city) VALUES
    ('meera@example.com', 'Chennai'),
    ('rohan@example.com', 'Mumbai'),
    ('zara@example.com',  NULL);          -- explicit NULL is NOT the same as DEFAULT
SELECT * FROM playground_02.newsletter ORDER BY id;

-- ---------------------------------------------------------------------
-- [Q02.05] Get generated values back immediately
-- Keywords: RETURNING
-- Business question: The app needs the new subscriber's id to show a welcome screen.
-- ---------------------------------------------------------------------
INSERT INTO playground_02.newsletter (email, city)
VALUES ('isha@example.com', 'Kochi')
RETURNING id, joined_at;

-- ---------------------------------------------------------------------
-- [Q02.06] Copy rows from a query
-- Keywords: INSERT INTO … SELECT
-- Business question: Subscribe every Prime member from Kerala addresses to the newsletter.
-- ---------------------------------------------------------------------
INSERT INTO playground_02.newsletter (email, city)
SELECT DISTINCT u.email::text, a.city
FROM core.users u
JOIN core.addresses a ON a.user_id = u.user_id AND a.is_default
WHERE u.is_prime AND a.state = 'Kerala';
SELECT count(*) AS subscribers_now FROM playground_02.newsletter;

-- ---------------------------------------------------------------------
-- [Q02.07] Force a value into a GENERATED ALWAYS identity column
-- Keywords: OVERRIDING SYSTEM VALUE
-- Business question: Migrate a legacy subscriber whose id (9001) must be preserved.
-- ---------------------------------------------------------------------
INSERT INTO playground_02.newsletter (id, email) OVERRIDING SYSTEM VALUE
VALUES (9001, 'legacy@example.com');

-- ---------------------------------------------------------------------
-- [Q02.08] Insert into a real app table, and undo it
-- Keywords: BEGIN, ROLLBACK, INSERT, RETURNING
-- Business question: Add a brand, look at it, then pretend it never happened.
-- ---------------------------------------------------------------------
BEGIN;
INSERT INTO catalog.brands (name, country_code, founded_year)
VALUES ('Chai Tech', 'IN', 2024)
RETURNING brand_id, name;
ROLLBACK;

-- =====================================================================
-- SECTION: VALUES as a table
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q02.09] VALUES on its own is a query that produces rows
-- Keywords: VALUES, column aliases (AS t(a, b))
-- Business question: A quick lookup table of shipping zones without creating a table.
-- ---------------------------------------------------------------------
SELECT *
FROM (VALUES ('north', 'New Delhi', 2), ('south', 'Bengaluru', 3), ('east', 'Kolkata', 4))
     AS zones(zone, hub_city, days_to_deliver);

-- =====================================================================
-- SECTION: Generating data
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q02.10] Integer series
-- Keywords: generate_series()
-- ---------------------------------------------------------------------
SELECT n FROM generate_series(1, 10, 3) AS n;      -- start, stop, step → 1,4,7,10

-- ---------------------------------------------------------------------
-- [Q02.11] Date / timestamp series
-- Keywords: generate_series(), interval
-- Business question: List the first day of each of the next 6 months (for a sales calendar).
-- ---------------------------------------------------------------------
SELECT d::date AS month_start
FROM generate_series(date_trunc('month', now()), date_trunc('month', now()) + interval '5 months', interval '1 month') AS d;

-- ---------------------------------------------------------------------
-- [Q02.12] Reproducible random data
-- Keywords: setseed(), random(), floor()
-- Note: After setseed() the sequence of random() values is the same every run.
-- ---------------------------------------------------------------------
SELECT setseed(0.5);
SELECT floor(random() * 6 + 1)::int AS dice_roll FROM generate_series(1, 5);

-- ---------------------------------------------------------------------
-- [Q02.13] Normally-distributed random numbers (PG16+) and random integers in a range (PG17)
-- Keywords: random_normal(), random(min, max)
-- Business question: Simulate 1,000 delivery times averaging 3 days (std-dev 1 day).
-- ---------------------------------------------------------------------
SELECT round(avg(t)::numeric, 2) AS avg_days, round(stddev(t)::numeric, 2) AS stddev_days,
       random(1, 100) AS a_random_int_1_to_100
FROM (SELECT random_normal(3, 1) AS t FROM generate_series(1, 1000)) s;

-- ---------------------------------------------------------------------
-- [Q02.14] Bulk-generate realistic rows
-- Keywords: INSERT … SELECT, generate_series(), md5(), gen_random_uuid(), array subscript
-- Business question: Create 10,000 fake gift-card codes for a promo.
-- ---------------------------------------------------------------------
CREATE TABLE playground_02.gift_cards (
    card_id   uuid PRIMARY KEY,
    code      text NOT NULL UNIQUE,
    value     numeric(8, 2) NOT NULL,
    campaign  text NOT NULL
);
INSERT INTO playground_02.gift_cards (card_id, code, value, campaign)
SELECT gen_random_uuid(),
       upper(substr(md5(g::text || 'salt'), 1, 12)),
       (ARRAY[250, 500, 1000, 2000])[1 + g % 4],
       'DIWALI-' || extract(year FROM now())
FROM generate_series(1, 10000) AS g;
SELECT value, count(*) FROM playground_02.gift_cards GROUP BY value ORDER BY value;

-- =====================================================================
-- SECTION: COPY — bulk import / export
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q02.15] Import a CSV file that lives on the SERVER
-- Keywords: COPY … FROM, FORMAT csv, HEADER
-- Business question: The partnerships team sent new brands as a CSV.
-- Note: Server-side COPY reads files on the DB server (here: inside the container at /playbook)
--       and needs superuser or the pg_read_server_files role. Empty CSV fields become NULL.
-- ---------------------------------------------------------------------
CREATE TABLE playground_02.brand_import (name text, country_code char(2), founded_year smallint);
COPY playground_02.brand_import (name, country_code, founded_year)
FROM '/playbook/chapters/02_seed_data/data/new_brands.csv'
WITH (FORMAT csv, HEADER true);
SELECT * FROM playground_02.brand_import;

-- ---------------------------------------------------------------------
-- [Q02.16] Export a table to the client
-- Keywords: COPY … TO STDOUT, DELIMITER
-- ---------------------------------------------------------------------
COPY playground_02.brand_import TO STDOUT WITH (FORMAT csv, HEADER true, DELIMITER '|');

-- ---------------------------------------------------------------------
-- [Q02.17] Export the result of a query to a server file
-- Keywords: COPY (query) TO 'file'
-- Business question: Dump yesterday's delivered orders for the finance team.
-- ---------------------------------------------------------------------
COPY (
    SELECT order_number, grand_total, placed_at
    FROM sales.orders
    WHERE status = 'delivered' AND placed_at >= now() - interval '30 days'
    ORDER BY placed_at
) TO '/tmp/recent_delivered_orders.csv' WITH (FORMAT csv, HEADER true);
SELECT pg_size_pretty((pg_stat_file('/tmp/recent_delivered_orders.csv')).size) AS exported_file_size;

-- ---------------------------------------------------------------------
-- [Q02.18] Client-side copy with psql's \copy (reads/writes files on YOUR machine)
-- Keywords: \copy
-- Note: Same options as COPY, but no special privileges required. It is a psql command,
--       so it must fit on one line. The file path is relative to where psql runs.
-- ---------------------------------------------------------------------
\copy (SELECT code, value FROM playground_02.gift_cards LIMIT 5) TO '/tmp/sample_gift_cards.csv' WITH (FORMAT csv, HEADER)
\copy playground_02.gift_cards (card_id, code, value, campaign) FROM PROGRAM 'echo "00000000-0000-0000-0000-000000000001,MANUALCODE01,100,MANUAL"' WITH (FORMAT csv)
SELECT * FROM playground_02.gift_cards WHERE campaign = 'MANUAL';
