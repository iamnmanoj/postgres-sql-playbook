-- =====================================================================
--  Chapter 01 · Solutions — DDL
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS playground_01;
DROP TABLE IF EXISTS playground_01.support_tickets, playground_01.gift_cards, playground_01.seller_snapshot;
DROP TYPE IF EXISTS playground_01.ticket_status;
DROP DOMAIN IF EXISTS playground_01.gstin;

-- [E01.01] Gift cards table
-- Keywords: CREATE TABLE, GENERATED ALWAYS AS IDENTITY, UNIQUE, CHECK, DEFAULT
CREATE TABLE playground_01.gift_cards (
    gift_card_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code         char(16) NOT NULL UNIQUE,
    balance      numeric(10, 2) NOT NULL CHECK (balance >= 0),
    expires_on   date NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);

-- [E01.02] Enum with a value inserted in the middle
-- Keywords: CREATE TYPE, AS ENUM, ALTER TYPE, ADD VALUE, AFTER
CREATE TYPE playground_01.ticket_status AS ENUM ('open', 'in_progress', 'closed');
ALTER TYPE playground_01.ticket_status ADD VALUE 'waiting_on_customer' AFTER 'in_progress';
SELECT enum_range(NULL::playground_01.ticket_status);

-- [E01.03] Tickets with two different ON DELETE behaviours
-- Keywords: REFERENCES, ON DELETE CASCADE, ON DELETE SET NULL
CREATE TABLE playground_01.support_tickets (
    ticket_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    bigint NOT NULL REFERENCES core.users (user_id) ON DELETE CASCADE,
    order_id   bigint REFERENCES sales.orders (order_id) ON DELETE SET NULL,
    status     playground_01.ticket_status NOT NULL DEFAULT 'open',
    subject    text NOT NULL,
    opened_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO playground_01.support_tickets (user_id, order_id, subject) VALUES (42, 1, 'Where is my order?');

-- [E01.04] GSTIN domain
-- Keywords: CREATE DOMAIN, CHECK, EXCEPTION
CREATE DOMAIN playground_01.gstin AS text CHECK (VALUE ~ '^[0-9A-Z]{15}$');
SELECT '27ABCDE1234F1Z5'::playground_01.gstin AS valid_value;
DO $$
BEGIN
    PERFORM 'bad-gstin'::playground_01.gstin;
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Rejected as expected: %', SQLERRM;
END $$;

-- [E01.05] Add then rename a constrained column
-- Keywords: ADD COLUMN, CHECK, RENAME COLUMN
ALTER TABLE playground_01.support_tickets
    ADD COLUMN priority smallint NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5);
ALTER TABLE playground_01.support_tickets RENAME COLUMN priority TO severity;

-- [E01.06] Generated columns must be IMMUTABLE (now() changes over time), so derive from data only
-- Keywords: GENERATED ALWAYS AS, STORED, left()
ALTER TABLE playground_01.gift_cards
    ADD COLUMN code_prefix text GENERATED ALWAYS AS (left(code, 4)) STORED;
INSERT INTO playground_01.gift_cards (code, balance, expires_on) VALUES ('DIWA1234ABCD5678', 500, current_date + 365);
SELECT code, code_prefix FROM playground_01.gift_cards;

-- [E01.07] Snapshot + primary key afterwards
-- Keywords: CREATE TABLE AS, ADD PRIMARY KEY
CREATE TABLE playground_01.seller_snapshot AS
SELECT seller_id, store_name, is_verified FROM core.sellers;
ALTER TABLE playground_01.seller_snapshot ADD PRIMARY KEY (seller_id);

-- [E01.08] Column count per table in the sales schema
-- Keywords: information_schema.columns, GROUP BY, count()
SELECT table_name, count(*) AS column_count
FROM information_schema.columns
WHERE table_schema = 'sales'
GROUP BY table_name
ORDER BY column_count DESC, table_name;
