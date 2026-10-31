-- =====================================================================
--  Chapter 19 · Security: roles, privileges, row-level security
--  Roles are CLUSTER-wide, so all demo roles are prefixed ss_ and dropped at the end.
--  RLS is demonstrated on copies in playground_19 (the superuser bypasses RLS anyway).
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- start clean (makes the script re-runnable)
DO $$
DECLARE r text;
BEGIN
    FOR r IN SELECT rolname FROM pg_roles WHERE rolname LIKE 'ss\_%' LOOP
        EXECUTE format('REASSIGN OWNED BY %I TO postgres', r);
        EXECUTE format('DROP OWNED BY %I', r);
        EXECUTE format('DROP ROLE %I', r);
    END LOOP;
END $$;
DROP SCHEMA IF EXISTS playground_19 CASCADE;
CREATE SCHEMA playground_19;
CREATE TABLE playground_19.order_items AS SELECT * FROM sales.order_items WHERE seller_id <= 5;
CREATE TABLE playground_19.orders AS
SELECT * FROM sales.orders WHERE order_id IN (SELECT order_id FROM playground_19.order_items);

-- =====================================================================
-- SECTION: Roles
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q19.01] Group roles (NOLOGIN) and user roles (LOGIN), membership
-- Keywords: CREATE ROLE, NOLOGIN, LOGIN, PASSWORD, VALID UNTIL, GRANT role TO role, INHERIT
-- Note: In PostgreSQL "users" and "groups" are both roles; CREATE USER = CREATE ROLE … LOGIN.
-- ---------------------------------------------------------------------
CREATE ROLE ss_readonly NOLOGIN;                                    -- a group: holds privileges
CREATE ROLE ss_analyst  LOGIN PASSWORD 'analyst-pw' VALID UNTIL '2030-01-01';
CREATE ROLE ss_support  LOGIN PASSWORD 'support-pw' CONNECTION LIMIT 5;
CREATE USER ss_seller_portal PASSWORD 'portal-pw';                  -- shorthand for LOGIN
GRANT ss_readonly TO ss_analyst;                                    -- analyst inherits readonly's privileges
SELECT r.rolname, r.rolcanlogin, r.rolinherit, r.rolconnlimit, r.rolvaliduntil,
       array(SELECT g.rolname FROM pg_auth_members m JOIN pg_roles g ON g.oid = m.roleid WHERE m.member = r.oid) AS member_of
FROM pg_roles r
WHERE r.rolname LIKE 'ss\_%'
ORDER BY r.rolname;

-- =====================================================================
-- SECTION: Privileges
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q19.02] Schema USAGE + table SELECT
-- Keywords: GRANT USAGE ON SCHEMA, GRANT SELECT ON ALL TABLES IN SCHEMA, CONNECT
-- Business question: Give the analytics team read-only access to catalog and sales.
-- ---------------------------------------------------------------------
DO $$ BEGIN EXECUTE format('GRANT CONNECT ON DATABASE %I TO ss_readonly', current_database()); END $$;
GRANT USAGE ON SCHEMA catalog, sales TO ss_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA catalog, sales TO ss_readonly;
SET ROLE ss_analyst;
SELECT current_user, count(*) AS orders_visible FROM sales.orders;
RESET ROLE;

-- ---------------------------------------------------------------------
-- [Q19.03] Without a grant: permission denied
-- Keywords: insufficient_privilege, has_table_privilege(), has_schema_privilege()
-- ---------------------------------------------------------------------
SELECT has_schema_privilege('ss_analyst', 'core', 'USAGE')          AS analyst_core_usage,
       has_table_privilege('ss_analyst', 'sales.orders', 'SELECT')  AS analyst_orders_select,
       has_table_privilege('ss_analyst', 'sales.orders', 'UPDATE')  AS analyst_orders_update;
SET ROLE ss_analyst;
DO $$
BEGIN
    PERFORM count(*) FROM core.users;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------
-- [Q19.04] Column-level privileges
-- Keywords: GRANT SELECT (columns), GRANT UPDATE (columns), has_column_privilege()
-- Business question: Support may read names/status and change status — but never see phone numbers.
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA core TO ss_support;
GRANT SELECT (user_id, full_name, status, created_at) ON core.users TO ss_support;
GRANT UPDATE (status) ON core.users TO ss_support;
SELECT has_column_privilege('ss_support', 'core.users', 'full_name', 'SELECT') AS can_read_name,
       has_column_privilege('ss_support', 'core.users', 'phone', 'SELECT')     AS can_read_phone;
SET ROLE ss_support;
SELECT user_id, full_name, status FROM core.users WHERE user_id = 1;
DO $$
BEGIN
    PERFORM phone FROM core.users WHERE user_id = 1;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------
-- [Q19.05] Remove privileges again
-- Keywords: REVOKE, REVOKE … FROM PUBLIC
-- Note: PUBLIC = every role. New functions are executable by PUBLIC by default; tables are not readable.
-- ---------------------------------------------------------------------
REVOKE UPDATE (status) ON core.users FROM ss_support;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;             -- hardening (default since PG15)
SELECT has_column_privilege('ss_support', 'core.users', 'status', 'UPDATE') AS can_still_update;

-- ---------------------------------------------------------------------
-- [Q19.06] Privileges for objects created in the FUTURE
-- Keywords: ALTER DEFAULT PRIVILEGES … GRANT … ON TABLES
-- Business question: New reporting tables should be readable by ss_readonly automatically.
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA playground_19 TO ss_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA playground_19 GRANT SELECT ON TABLES TO ss_readonly;
CREATE TABLE playground_19.new_report (id int);
SELECT has_table_privilege('ss_analyst', 'playground_19.new_report', 'SELECT') AS analyst_can_read_new_table;

-- ---------------------------------------------------------------------
-- [Q19.07] Functions and sequences need their own grants
-- Keywords: GRANT EXECUTE ON FUNCTION, REVOKE EXECUTE … FROM PUBLIC, GRANT USAGE ON SEQUENCE
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION playground_19.order_count(p_user bigint) RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog
AS $$ SELECT count(*) FROM sales.orders WHERE user_id = p_user $$;
REVOKE EXECUTE ON FUNCTION playground_19.order_count(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION playground_19.order_count(bigint) TO ss_support;
CREATE SEQUENCE playground_19.ticket_seq;
GRANT USAGE ON SEQUENCE playground_19.ticket_seq TO ss_support;
GRANT USAGE ON SCHEMA playground_19 TO ss_support;
SET ROLE ss_support;
SELECT playground_19.order_count(42) AS via_definer_function, nextval('playground_19.ticket_seq') AS ticket_no;
RESET ROLE;

-- ---------------------------------------------------------------------
-- [Q19.08] Who am I? Switching identity
-- Keywords: SET ROLE, RESET ROLE, current_user, session_user, SET SESSION AUTHORIZATION
-- ---------------------------------------------------------------------
SET ROLE ss_analyst;
SELECT session_user AS logged_in_as, current_user AS acting_as;
RESET ROLE;
SELECT session_user, current_user;

-- ---------------------------------------------------------------------
-- [Q19.09] Inspect grants
-- Keywords: information_schema.role_table_grants, aclexplode(), relacl / attacl, \dp
-- ---------------------------------------------------------------------
SELECT grantee, table_schema || '.' || table_name AS table_name, string_agg(privilege_type, ', ') AS privileges
FROM information_schema.role_table_grants
WHERE grantee LIKE 'ss\_%'
GROUP BY grantee, table_schema, table_name
ORDER BY grantee, table_name
LIMIT 8;
SELECT a.attname AS column_name, x.grantee::regrole AS grantee, x.privilege_type    -- column grants live in attacl
FROM pg_attribute a, aclexplode(a.attacl) x
WHERE a.attrelid = 'core.users'::regclass AND a.attacl IS NOT NULL
ORDER BY a.attnum;

-- =====================================================================
-- SECTION: Row-level security (RLS)
-- =====================================================================
GRANT SELECT, INSERT, UPDATE ON playground_19.order_items, playground_19.orders TO ss_seller_portal;
GRANT USAGE ON SCHEMA playground_19 TO ss_seller_portal;

-- ---------------------------------------------------------------------
-- [Q19.10] Multi-tenant isolation: each seller sees only their own rows
-- Keywords: ALTER TABLE … ENABLE ROW LEVEL SECURITY, CREATE POLICY … USING, current_setting(…, true)
-- Business question: The seller portal connects as ONE database role; the app sets app.seller_id per request.
-- ---------------------------------------------------------------------
ALTER TABLE playground_19.order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY seller_isolation ON playground_19.order_items
    USING (seller_id = current_setting('app.seller_id', true)::bigint);
SET ROLE ss_seller_portal;
SELECT count(*) AS rows_without_seller_context FROM playground_19.order_items;      -- 0: setting missing → NULL → no rows
SET app.seller_id = '3';
SELECT seller_id, count(*) AS rows_visible FROM playground_19.order_items GROUP BY seller_id;
RESET app.seller_id;
RESET ROLE;
SELECT count(DISTINCT seller_id) AS superuser_sees_sellers FROM playground_19.order_items;   -- superusers bypass RLS

-- ---------------------------------------------------------------------
-- [Q19.11] Stop tenants from writing rows for someone else
-- Keywords: WITH CHECK, FOR INSERT, new row violates row-level security policy
-- ---------------------------------------------------------------------
CREATE POLICY seller_insert ON playground_19.order_items FOR INSERT
    WITH CHECK (seller_id = current_setting('app.seller_id', true)::bigint);
SET ROLE ss_seller_portal;
SET app.seller_id = '3';
INSERT INTO playground_19.order_items (order_item_id, order_id, variant_id, seller_id, quantity, unit_price, discount, line_total)
VALUES (-1, 1, 1, 3, 1, 100, 0, 100);                                                -- own seller: OK
DO $$
BEGIN
    INSERT INTO playground_19.order_items (order_item_id, order_id, variant_id, seller_id, quantity, unit_price, discount, line_total)
    VALUES (-2, 1, 1, 4, 1, 100, 0, 100);                                            -- another seller
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;
RESET app.seller_id;
RESET ROLE;

-- ---------------------------------------------------------------------
-- [Q19.12] Per-command and per-role policies
-- Keywords: CREATE POLICY … FOR SELECT / FOR UPDATE … TO role, USING vs WITH CHECK on UPDATE
-- Business question: Sellers see orders that contain their items, but may only edit the notes column of pending ones.
-- ---------------------------------------------------------------------
ALTER TABLE playground_19.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY seller_reads_orders ON playground_19.orders FOR SELECT TO ss_seller_portal
    USING (EXISTS (SELECT 1 FROM playground_19.order_items oi
                   WHERE oi.order_id = orders.order_id
                     AND oi.seller_id = current_setting('app.seller_id', true)::bigint));
CREATE POLICY seller_edits_pending ON playground_19.orders FOR UPDATE TO ss_seller_portal
    USING (status = 'pending')                         -- which existing rows may be updated
    WITH CHECK (status = 'pending');                   -- what the row may look like afterwards
SET ROLE ss_seller_portal;
SET app.seller_id = '2';
SELECT count(*) AS orders_seller_2_can_see FROM playground_19.orders;
UPDATE playground_19.orders SET notes = 'Packed with care' WHERE status = 'delivered';   -- 0 rows: policy blocks
RESET app.seller_id;
RESET ROLE;

-- ---------------------------------------------------------------------
-- [Q19.13] RESTRICTIVE policies are AND-ed with the permissive ones
-- Keywords: AS PERMISSIVE (default, OR-ed), AS RESTRICTIVE (AND-ed)
-- Business question: Whatever else is allowed, sellers must never see cancelled orders.
-- ---------------------------------------------------------------------
CREATE POLICY hide_cancelled ON playground_19.orders AS RESTRICTIVE FOR SELECT TO ss_seller_portal
    USING (status <> 'cancelled');
SET ROLE ss_seller_portal;
SET app.seller_id = '2';
SELECT status, count(*) FROM playground_19.orders GROUP BY status ORDER BY status;
RESET app.seller_id;
RESET ROLE;

-- ---------------------------------------------------------------------
-- [Q19.14] Table owners bypass RLS unless FORCEd; roles can be given BYPASSRLS
-- Keywords: FORCE ROW LEVEL SECURITY, BYPASSRLS, relrowsecurity, relforcerowsecurity, pg_policies
-- ---------------------------------------------------------------------
ALTER TABLE playground_19.order_items FORCE ROW LEVEL SECURITY;
CREATE ROLE ss_auditor NOLOGIN BYPASSRLS;
SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class WHERE relnamespace = 'playground_19'::regnamespace AND relkind = 'r';
SELECT tablename, policyname, permissive, roles, cmd, qual FROM pg_policies WHERE schemaname = 'playground_19';

-- ---------------------------------------------------------------------
-- [Q19.15] Views and RLS: use security_invoker so the CALLER's policies apply
-- Keywords: security_invoker view + RLS
-- ---------------------------------------------------------------------
CREATE VIEW playground_19.my_sales WITH (security_invoker = true) AS
SELECT seller_id, sum(line_total) AS revenue, count(*) AS items FROM playground_19.order_items GROUP BY seller_id;
GRANT SELECT ON playground_19.my_sales TO ss_seller_portal;
SET ROLE ss_seller_portal;
SET app.seller_id = '5';
SELECT * FROM playground_19.my_sales;                                               -- only seller 5
RESET app.seller_id;
RESET ROLE;

-- =====================================================================
-- SECTION: Secrets & cleanup
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q19.16] Store passwords as salted hashes, never in plain text
-- Keywords: pgcrypto, crypt(), gen_salt('bf')
-- Business question: Seller-portal sub-accounts with bcrypt-hashed passwords.
-- ---------------------------------------------------------------------
CREATE TABLE playground_19.portal_accounts (login text PRIMARY KEY, password_hash text NOT NULL);
INSERT INTO playground_19.portal_accounts VALUES ('store3-admin', crypt('S3cret!', gen_salt('bf', 8)));
SELECT login,
       left(password_hash, 7) || '…'                          AS hash_prefix,
       password_hash = crypt('S3cret!', password_hash)         AS correct_password,
       password_hash = crypt('guess', password_hash)           AS wrong_password
FROM playground_19.portal_accounts;

-- ---------------------------------------------------------------------
-- [Q19.17] Remove roles cleanly
-- Keywords: REASSIGN OWNED BY, DROP OWNED BY, DROP ROLE
-- Note: A role can't be dropped while it owns objects or holds privileges in ANY database.
-- ---------------------------------------------------------------------
DROP SCHEMA playground_19 CASCADE;
DO $$
DECLARE r text;
BEGIN
    FOR r IN SELECT rolname FROM pg_roles WHERE rolname LIKE 'ss\_%' LOOP
        EXECUTE format('REASSIGN OWNED BY %I TO postgres', r);   -- give away owned objects
        EXECUTE format('DROP OWNED BY %I', r);                    -- revoke all its privileges
        EXECUTE format('DROP ROLE %I', r);
    END LOOP;
END $$;
SELECT count(*) AS ss_roles_left FROM pg_roles WHERE rolname LIKE 'ss\_%';
