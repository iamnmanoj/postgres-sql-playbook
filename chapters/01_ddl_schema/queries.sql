-- =====================================================================
--  Chapter 01 · DDL — designing tables, types and constraints
--  Everything here happens in a throw-away schema: playground_01.
--  The real ShopSphere schema lives in schema.sql (read it next!).
-- =====================================================================

-- =====================================================================
-- SECTION: Schemas
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q01.01] Create (or re-create) a sandbox schema
-- Keywords: DROP SCHEMA, IF EXISTS, CASCADE, CREATE SCHEMA
-- Business question: Where can I experiment without touching the shop's real tables?
-- ---------------------------------------------------------------------
DROP SCHEMA IF EXISTS playground_01 CASCADE;   -- CASCADE also drops everything inside it
CREATE SCHEMA playground_01;

-- ---------------------------------------------------------------------
-- [Q01.02] Make the sandbox the default place for new objects
-- Keywords: SET, search_path, SHOW
-- Note: search_path is the list of schemas PostgreSQL searches for unqualified names.
-- ---------------------------------------------------------------------
SET search_path = playground_01, core, catalog, logistics, sales, audit, analytics, public;
SHOW search_path;

-- =====================================================================
-- SECTION: Data types tour
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q01.03] One table that shows the most common PostgreSQL data types
-- Keywords: CREATE TABLE, smallint, integer, bigint, numeric, real, double precision, text, varchar, char, boolean, date, time, timestamp, timestamptz, interval, uuid, bytea, inet, cidr, jsonb
-- Business question: Which type should each kind of value use?
-- ---------------------------------------------------------------------
CREATE TABLE playground_01.type_tour (
    qty_small      smallint,            -- -32,768 .. 32,767 (2 bytes)
    qty            integer,             -- ±2.1 billion (4 bytes)
    big_counter    bigint,              -- ±9.2 quintillion (8 bytes): use for ids
    price          numeric(12, 2),      -- exact decimal, so ALWAYS use it for money
    ratio_float    real,                -- 6 digits, inexact
    score_double   double precision,    -- 15 digits, inexact (science, ML)
    description    text,                -- unlimited length, the usual choice
    country_name   varchar(60),         -- text with a max length
    country_code   char(2),             -- fixed length, blank padded
    is_gift        boolean,             -- true / false / NULL
    birthday       date,                -- calendar date
    opens_at       time,                -- time of day
    local_ts       timestamp,           -- date+time WITHOUT time zone
    event_ts       timestamptz,         -- date+time WITH time zone (stored in UTC) <- prefer this
    delivery_sla   interval,            -- a duration: '3 days 4 hours'
    public_id      uuid,                -- 128-bit identifier
    thumbnail      bytea,               -- raw bytes
    client_ip      inet,                -- IP address
    office_network cidr,                -- network block
    extra          jsonb                -- binary JSON document
);

INSERT INTO playground_01.type_tour VALUES
    (5, 120000, 9000000000, 1499.99, 0.1, 0.1, 'Cotton tee', 'India', 'IN', true,
     '1995-08-15', '09:30', '2025-01-01 10:00', '2025-01-01 10:00+05:30', '3 days 4 hours',
     gen_random_uuid(), '\xDEADBEEF', '192.168.1.20', '10.0.0.0/8', '{"wrap": "red"}');

SELECT * FROM playground_01.type_tour;

-- ---------------------------------------------------------------------
-- [Q01.04] Why money must be numeric, not floating point
-- Keywords: numeric, double precision, ::
-- Business question: Do 10 items of ₹0.10 add up to exactly ₹1.00?
-- ---------------------------------------------------------------------
SELECT 0.1::double precision * 3 = 0.3::double precision AS float_equal,   -- false!
       0.1::numeric * 3 = 0.3::numeric                     AS numeric_equal; -- true

-- =====================================================================
-- SECTION: Constraints
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q01.05] A table with column constraints
-- Keywords: PRIMARY KEY, NOT NULL, DEFAULT, UNIQUE, CHECK, GENERATED ALWAYS AS IDENTITY, now()
-- Business question: Model a newsletter subscriber list with sensible rules.
-- ---------------------------------------------------------------------
CREATE TABLE playground_01.subscribers (
    subscriber_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   -- auto number
    email         text NOT NULL UNIQUE,
    name          text NOT NULL DEFAULT 'Friend',
    age           int CHECK (age >= 13),                          -- column-level CHECK
    subscribed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO playground_01.subscribers (email, age) VALUES ('meera@example.com', 29);
SELECT * FROM playground_01.subscribers;

-- ---------------------------------------------------------------------
-- [Q01.06] Named table-level constraints spanning several columns
-- Keywords: CONSTRAINT, CHECK, UNIQUE
-- Business question: A flash sale must end after it starts, and a product can be in a sale only once.
-- ---------------------------------------------------------------------
CREATE TABLE playground_01.flash_sales (
    sale_id     int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id  bigint NOT NULL,
    starts_at   timestamptz NOT NULL,
    ends_at     timestamptz NOT NULL,
    discount_pct numeric(5, 2) NOT NULL,
    CONSTRAINT flash_sales_valid_window CHECK (ends_at > starts_at),
    CONSTRAINT flash_sales_pct_range    CHECK (discount_pct > 0 AND discount_pct <= 90),
    CONSTRAINT flash_sales_one_per_product UNIQUE (product_id, starts_at)
);

-- ---------------------------------------------------------------------
-- [Q01.07] See a constraint violation (caught so the script continues)
-- Keywords: DO, EXCEPTION, RAISE NOTICE, SQLERRM
-- Business question: What happens if someone creates a sale that ends before it starts?
-- ---------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO playground_01.flash_sales (product_id, starts_at, ends_at, discount_pct)
    VALUES (1, now(), now() - interval '1 hour', 20);
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- [Q01.08] UNIQUE treats NULLs as distinct, unless you say NULLS NOT DISTINCT (PG15+)
-- Keywords: UNIQUE NULLS NOT DISTINCT
-- Business question: Allow only ONE "global" (seller_id IS NULL) banner per slot.
-- ---------------------------------------------------------------------
CREATE TABLE playground_01.home_banners (
    slot      text NOT NULL,
    seller_id bigint,
    image_url text NOT NULL,
    CONSTRAINT home_banners_slot_seller UNIQUE NULLS NOT DISTINCT (slot, seller_id)
);
INSERT INTO playground_01.home_banners VALUES ('hero', NULL, 'a.jpg');
DO $$
BEGIN
    INSERT INTO playground_01.home_banners VALUES ('hero', NULL, 'b.jpg');   -- rejected
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- [Q01.09] Composite primary key + foreign keys with different ON DELETE actions
-- Keywords: FOREIGN KEY, REFERENCES, ON DELETE CASCADE, ON DELETE RESTRICT, ON DELETE SET NULL, ON UPDATE CASCADE
-- Business question: Model gift registries: deleting a registry deletes its items, but a product in a registry can't be deleted.
-- ---------------------------------------------------------------------
CREATE TABLE playground_01.registries (
    registry_id int PRIMARY KEY,
    owner_name  text NOT NULL,
    code        text UNIQUE
);
CREATE TABLE playground_01.registry_products (
    product_code text PRIMARY KEY,
    name         text NOT NULL
);
CREATE TABLE playground_01.registry_items (
    registry_id  int  NOT NULL REFERENCES playground_01.registries (registry_id) ON DELETE CASCADE,
    product_code text NOT NULL REFERENCES playground_01.registry_products (product_code)
                                ON DELETE RESTRICT ON UPDATE CASCADE,
    reserved_by  int  REFERENCES playground_01.subscribers (subscriber_id) ON DELETE SET NULL,
    quantity     int  NOT NULL DEFAULT 1,
    PRIMARY KEY (registry_id, product_code)                    -- composite key
);
INSERT INTO playground_01.registries VALUES (1, 'Asha & Rohan', 'WED2025');
INSERT INTO playground_01.registry_products VALUES ('KETTLE', 'Electric Kettle'), ('MIXER', 'Mixer Grinder');
INSERT INTO playground_01.registry_items (registry_id, product_code) VALUES (1, 'KETTLE'), (1, 'MIXER');
UPDATE playground_01.registry_products SET product_code = 'KETTLE-2L' WHERE product_code = 'KETTLE';  -- cascades
SELECT * FROM playground_01.registry_items;
DELETE FROM playground_01.registries WHERE registry_id = 1;                                        -- cascades
SELECT count(*) AS items_left FROM playground_01.registry_items;

-- ---------------------------------------------------------------------
-- [Q01.10] A deferrable foreign key: checked at COMMIT, not per statement
-- Keywords: DEFERRABLE, INITIALLY DEFERRED
-- Business question: Insert an employee and their manager in any order inside one transaction.
-- ---------------------------------------------------------------------
CREATE TABLE playground_01.support_agents (
    agent_id   int PRIMARY KEY,
    name       text NOT NULL,
    manager_id int REFERENCES playground_01.support_agents (agent_id) DEFERRABLE INITIALLY DEFERRED
);
BEGIN;
INSERT INTO playground_01.support_agents VALUES (2, 'Kabir', 1);   -- manager 1 doesn't exist yet: OK for now
INSERT INTO playground_01.support_agents VALUES (1, 'Neha', NULL);
COMMIT;                                                            -- FK checked here
SELECT * FROM playground_01.support_agents;

-- =====================================================================
-- SECTION: Identity, serial and sequences
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q01.11] IDENTITY (modern, SQL standard) vs SERIAL (legacy shorthand)
-- Keywords: GENERATED BY DEFAULT AS IDENTITY, serial, bigserial
-- Note: ALWAYS rejects manual values; BY DEFAULT allows them. serial = int + sequence + default.
-- ---------------------------------------------------------------------
CREATE TABLE playground_01.tickets_identity (id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, subject text);
CREATE TABLE playground_01.tickets_serial   (id bigserial PRIMARY KEY, subject text);
INSERT INTO playground_01.tickets_identity (subject) VALUES ('Late delivery');
INSERT INTO playground_01.tickets_identity (id, subject) VALUES (100, 'Manual id is allowed with BY DEFAULT');
INSERT INTO playground_01.tickets_serial (subject) VALUES ('Wrong size');
SELECT 'identity' AS kind, * FROM playground_01.tickets_identity
UNION ALL
SELECT 'serial', * FROM playground_01.tickets_serial;

-- ---------------------------------------------------------------------
-- [Q01.12] A standalone sequence for human-friendly invoice numbers
-- Keywords: CREATE SEQUENCE, START WITH, INCREMENT BY, nextval(), currval(), setval()
-- Business question: Generate invoice numbers INV-10000, INV-10005, ...
-- ---------------------------------------------------------------------
CREATE SEQUENCE playground_01.invoice_seq START WITH 10000 INCREMENT BY 5;
SELECT 'INV-' || nextval('playground_01.invoice_seq') AS first_invoice,
       'INV-' || nextval('playground_01.invoice_seq') AS second_invoice;
SELECT currval('playground_01.invoice_seq') AS last_value_in_this_session;
SELECT setval('playground_01.invoice_seq', 50000) AS jumped_to;

-- =====================================================================
-- SECTION: Custom types: ENUM, composite, DOMAIN
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q01.13] An ENUM type and adding a new label later
-- Keywords: CREATE TYPE, AS ENUM, ALTER TYPE, ADD VALUE, BEFORE, enum_range()
-- Business question: Ticket priorities need a new 'urgent' level above 'high'.
-- ---------------------------------------------------------------------
CREATE TYPE playground_01.ticket_priority AS ENUM ('low', 'medium', 'high');
ALTER TYPE playground_01.ticket_priority ADD VALUE 'urgent' AFTER 'high';
ALTER TYPE playground_01.ticket_priority ADD VALUE 'trivial' BEFORE 'low';
SELECT enum_range(NULL::playground_01.ticket_priority) AS all_labels_in_order;

-- ---------------------------------------------------------------------
-- [Q01.14] A composite type: a reusable "record shape"
-- Keywords: CREATE TYPE, AS (composite), ROW()
-- Business question: Store a package's dimensions as one value.
-- ---------------------------------------------------------------------
CREATE TYPE playground_01.dimensions AS (length_cm numeric, width_cm numeric, height_cm numeric);
CREATE TABLE playground_01.parcels (
    parcel_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    size      playground_01.dimensions
);
INSERT INTO playground_01.parcels (size) VALUES (ROW(30, 20, 10)), (ROW(60, 40, 40));
SELECT parcel_id, (size).length_cm, (size).length_cm * (size).width_cm * (size).height_cm AS volume_cm3
FROM playground_01.parcels;

-- ---------------------------------------------------------------------
-- [Q01.15] A DOMAIN: base type + reusable validation
-- Keywords: CREATE DOMAIN, CHECK, VALUE
-- Business question: Indian PIN codes are always 6 digits; validate them everywhere.
-- ---------------------------------------------------------------------
CREATE DOMAIN playground_01.pincode AS text CHECK (VALUE ~ '^[1-9][0-9]{5}$');
CREATE TABLE playground_01.serviceable_pincodes (pincode playground_01.pincode PRIMARY KEY, cod_allowed boolean NOT NULL);
INSERT INTO playground_01.serviceable_pincodes VALUES ('560001', true), ('110001', false);
DO $$
BEGIN
    INSERT INTO playground_01.serviceable_pincodes VALUES ('06A001', true);
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

-- =====================================================================
-- SECTION: Generated columns
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q01.16] A stored generated column
-- Keywords: GENERATED ALWAYS AS, STORED
-- Business question: Keep a cart line's total always equal to qty × price.
-- ---------------------------------------------------------------------
CREATE TABLE playground_01.cart_lines (
    line_id    int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    qty        int NOT NULL,
    unit_price numeric(10, 2) NOT NULL,
    line_total numeric(12, 2) GENERATED ALWAYS AS (qty * unit_price) STORED
);
INSERT INTO playground_01.cart_lines (qty, unit_price) VALUES (3, 199.50);
SELECT * FROM playground_01.cart_lines;

-- =====================================================================
-- SECTION: Changing tables — ALTER TABLE
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q01.17] Add, rename and drop columns
-- Keywords: ALTER TABLE, ADD COLUMN, RENAME COLUMN, DROP COLUMN, IF NOT EXISTS
-- Business question: Subscribers now need a phone number; 'name' should be 'display_name'.
-- ---------------------------------------------------------------------
ALTER TABLE playground_01.subscribers ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE playground_01.subscribers ADD COLUMN source text DEFAULT 'website';
ALTER TABLE playground_01.subscribers RENAME COLUMN name TO display_name;
ALTER TABLE playground_01.subscribers DROP COLUMN IF EXISTS phone;
SELECT * FROM playground_01.subscribers;

-- ---------------------------------------------------------------------
-- [Q01.18] Change a column's type, converting existing data
-- Keywords: ALTER COLUMN, TYPE, USING
-- Business question: 'age' was int; marketing wants an age-band text instead.
-- ---------------------------------------------------------------------
ALTER TABLE playground_01.subscribers
    DROP CONSTRAINT subscribers_age_check,
    ALTER COLUMN age TYPE text USING (CASE WHEN age < 25 THEN '18-24' WHEN age < 35 THEN '25-34' ELSE '35+' END);
SELECT email, age AS age_band FROM playground_01.subscribers;

-- ---------------------------------------------------------------------
-- [Q01.19] Change defaults and nullability
-- Keywords: SET DEFAULT, DROP DEFAULT, SET NOT NULL, DROP NOT NULL
-- ---------------------------------------------------------------------
ALTER TABLE playground_01.subscribers ALTER COLUMN source SET DEFAULT 'app';
ALTER TABLE playground_01.subscribers ALTER COLUMN source SET NOT NULL;
ALTER TABLE playground_01.subscribers ALTER COLUMN display_name DROP DEFAULT;
ALTER TABLE playground_01.subscribers ALTER COLUMN age DROP NOT NULL;   -- no-op here but legal

-- ---------------------------------------------------------------------
-- [Q01.20] Add a constraint to a big table without locking it for long
-- Keywords: ADD CONSTRAINT, NOT VALID, VALIDATE CONSTRAINT
-- Business question: Enforce lowercase emails from now on, then check old rows later.
-- Note: NOT VALID skips checking existing rows; VALIDATE checks them with a weaker lock.
-- ---------------------------------------------------------------------
ALTER TABLE playground_01.subscribers
    ADD CONSTRAINT subscribers_email_lower CHECK (email = lower(email)) NOT VALID;
ALTER TABLE playground_01.subscribers VALIDATE CONSTRAINT subscribers_email_lower;

-- ---------------------------------------------------------------------
-- [Q01.21] Rename a table and move it to another schema
-- Keywords: RENAME TO, SET SCHEMA
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS playground_01_archive;
ALTER TABLE playground_01.tickets_serial RENAME TO old_tickets;
ALTER TABLE playground_01.old_tickets SET SCHEMA playground_01_archive;
SELECT table_schema, table_name FROM information_schema.tables WHERE table_name = 'old_tickets';
DROP SCHEMA playground_01_archive CASCADE;

-- =====================================================================
-- SECTION: Creating tables from other tables
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q01.22] CREATE TABLE AS: snapshot a query result into a new table
-- Keywords: CREATE TABLE AS, WITH NO DATA
-- Business question: Freeze today's list of premium (Prime) customers for a campaign.
-- ---------------------------------------------------------------------
CREATE TABLE playground_01.prime_snapshot AS
SELECT user_id, email, created_at FROM core.users WHERE is_prime AND status = 'active';
CREATE TABLE playground_01.prime_snapshot_empty AS
SELECT * FROM playground_01.prime_snapshot WITH NO DATA;        -- same columns, zero rows
SELECT (SELECT count(*) FROM playground_01.prime_snapshot) AS copied,
       (SELECT count(*) FROM playground_01.prime_snapshot_empty) AS empty_copy;

-- ---------------------------------------------------------------------
-- [Q01.23] Copy a table's structure including constraints, defaults and indexes
-- Keywords: LIKE, INCLUDING ALL
-- Business question: Create an archive table shaped exactly like sales.coupons.
-- ---------------------------------------------------------------------
CREATE TABLE playground_01.coupons_archive (LIKE sales.coupons INCLUDING ALL);
SELECT column_name, data_type, column_default IS NOT NULL AS has_default
FROM information_schema.columns
WHERE table_schema = 'playground_01' AND table_name = 'coupons_archive'
ORDER BY ordinal_position;

-- ---------------------------------------------------------------------
-- [Q01.24] Temporary and unlogged tables
-- Keywords: CREATE TEMP TABLE, ON COMMIT DROP, UNLOGGED
-- Note: TEMP tables are private to your session; UNLOGGED tables are fast but emptied after a crash.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE my_basket (variant_id bigint, qty int);
INSERT INTO my_basket VALUES (1, 2), (5, 1);
SELECT * FROM my_basket;
BEGIN;
CREATE TEMP TABLE scratch_calc (x int) ON COMMIT DROP;   -- disappears at COMMIT
COMMIT;
CREATE UNLOGGED TABLE playground_01.page_cache (url text PRIMARY KEY, html text, cached_at timestamptz DEFAULT now());

-- =====================================================================
-- SECTION: Documenting and inspecting
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q01.25] Attach documentation to objects and read it back
-- Keywords: COMMENT ON, obj_description(), col_description()
-- ---------------------------------------------------------------------
COMMENT ON TABLE  playground_01.subscribers IS 'Newsletter subscribers (demo)';
COMMENT ON COLUMN playground_01.subscribers.source IS 'Where the sign-up came from';
SELECT obj_description('playground_01.subscribers'::regclass, 'pg_class') AS table_comment,
       col_description('playground_01.subscribers'::regclass, 5)          AS fifth_column_comment;

-- ---------------------------------------------------------------------
-- [Q01.26] Inspect any table's columns via the SQL-standard information_schema
-- Keywords: information_schema.columns, is_nullable, column_default
-- Business question: What columns does sales.orders have, and which are generated?
-- ---------------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default, is_generated
FROM information_schema.columns
WHERE table_schema = 'sales' AND table_name = 'orders'
ORDER BY ordinal_position;

-- =====================================================================
-- SECTION: Dropping things
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q01.27] DROP with RESTRICT (default) vs CASCADE
-- Keywords: DROP TABLE, RESTRICT, CASCADE, DROP TYPE
-- Business question: Why can't I drop a type that a table still uses?
-- ---------------------------------------------------------------------
DO $$
BEGIN
    DROP TYPE playground_01.dimensions RESTRICT;      -- parcels.size depends on it
EXCEPTION WHEN dependent_objects_still_exist THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;
DROP TYPE playground_01.dimensions CASCADE;           -- drops the dependent COLUMN too
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'playground_01' AND table_name = 'parcels';
DROP TABLE IF EXISTS playground_01.page_cache, playground_01.prime_snapshot_empty;

RESET search_path;
