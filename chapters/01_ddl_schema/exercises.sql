-- =====================================================================
--  Chapter 01 · Exercises — DDL
--  Work in your own schema: CREATE SCHEMA IF NOT EXISTS playground_01;
--  Answers: solutions.sql
-- =====================================================================

-- [E01.01] (easy) Create a table playground_01.gift_cards with: an identity primary key,
--          a unique 16-character code (char(16)), a balance (money-safe type) that can never
--          be negative, an expiry date, and a created_at defaulting to now().

-- [E01.02] (easy) Create an ENUM playground_01.ticket_status with 'open','in_progress','closed'
--          and then add 'waiting_on_customer' between 'in_progress' and 'closed'.

-- [E01.03] (medium) Create playground_01.support_tickets referencing core.users (user_id) and
--          sales.orders (order_id). Deleting a user must delete their tickets; deleting an order
--          must keep the ticket but blank out order_id. Use the enum from E01.02 with default 'open'.

-- [E01.04] (medium) Create a DOMAIN playground_01.gstin for Indian GST numbers:
--          exactly 15 upper-case letters/digits. Test it with a valid and an invalid value
--          (catch the error in a DO block).

-- [E01.05] (medium) Add a column priority smallint to support_tickets with default 3 and a
--          CHECK that it is between 1 and 5. Then rename the column to severity.

-- [E01.06] (medium) Add a stored generated column to gift_cards called is_expired_on_creation
--          ... trick question! Why can't a generated column use now()? Instead add a generated
--          column code_prefix = first 4 characters of code.

-- [E01.07] (hard) Snapshot every seller's store_name and verification flag into
--          playground_01.seller_snapshot using CREATE TABLE AS, then add a primary key to it.

-- [E01.08] (hard) Using information_schema, list every table in the sales schema together with
--          the number of columns it has, biggest first.
