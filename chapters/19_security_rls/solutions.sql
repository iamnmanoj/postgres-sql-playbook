-- =====================================================================
--  Chapter 19 · Solutions — security, roles & row-level security
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
DO $$
DECLARE r text;
BEGIN
    FOR r IN SELECT rolname FROM pg_roles WHERE rolname LIKE 'ss\_ex19\_%' LOOP
        EXECUTE format('REASSIGN OWNED BY %I TO postgres', r);
        EXECUTE format('DROP OWNED BY %I', r);
        EXECUTE format('DROP ROLE %I', r);
    END LOOP;
END $$;
CREATE SCHEMA IF NOT EXISTS playground_19;
DROP TABLE IF EXISTS playground_19.addresses;

-- [E19.01] Group + member
-- Keywords: CREATE ROLE, NOLOGIN, LOGIN, GRANT role TO role
CREATE ROLE ss_ex19_finance NOLOGIN;
CREATE ROLE ss_ex19_priya LOGIN PASSWORD 'priya-pw' IN ROLE ss_ex19_finance;
SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname LIKE 'ss\_ex19\_%' ORDER BY rolname;

-- [E19.02] Table grants and checks
-- Keywords: GRANT USAGE, GRANT SELECT, has_table_privilege()
GRANT USAGE ON SCHEMA sales TO ss_ex19_finance;
GRANT SELECT ON sales.payments, sales.refunds TO ss_ex19_finance;
SELECT has_table_privilege('ss_ex19_priya', 'sales.payments', 'SELECT') AS payments,
       has_table_privilege('ss_ex19_priya', 'sales.orders', 'SELECT')   AS orders;

-- [E19.03] Column grants
-- Keywords: GRANT SELECT (cols), has_column_privilege()
GRANT USAGE ON SCHEMA core TO ss_ex19_finance;
GRANT SELECT (user_id, email) ON core.users TO ss_ex19_finance;
SELECT has_column_privilege('ss_ex19_priya', 'core.users', 'email', 'SELECT') AS email,
       has_column_privilege('ss_ex19_priya', 'core.users', 'phone', 'SELECT') AS phone;

-- [E19.04] RLS on a copy of addresses
-- Keywords: ENABLE ROW LEVEL SECURITY, CREATE POLICY, SET ROLE, current_setting()
CREATE ROLE ss_ex19_customer NOLOGIN;
CREATE TABLE playground_19.addresses AS SELECT * FROM core.addresses;
ALTER TABLE playground_19.addresses ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_addresses ON playground_19.addresses
    USING (user_id = current_setting('app.user_id', true)::bigint);
GRANT USAGE ON SCHEMA playground_19 TO ss_ex19_customer;
GRANT SELECT ON playground_19.addresses TO ss_ex19_customer;
SET ROLE ss_ex19_customer;
SET app.user_id = '42';
SELECT user_id, label, city FROM playground_19.addresses;
RESET app.user_id;
RESET ROLE;

-- [E19.05] bcrypt
-- Keywords: crypt(), gen_salt('bf', 10)
WITH h AS (SELECT crypt('Diwali2025!', gen_salt('bf', 10)) AS hash)
SELECT hash = crypt('Diwali2025!', hash) AS correct, hash = crypt('diwali2025', hash) AS wrong FROM h;

-- [E19.06] Clean up
-- Keywords: DROP TABLE, REASSIGN OWNED, DROP OWNED, DROP ROLE
DROP TABLE playground_19.addresses;
DO $$
DECLARE r text;
BEGIN
    FOR r IN SELECT rolname FROM pg_roles WHERE rolname LIKE 'ss\_ex19\_%' LOOP
        EXECUTE format('REASSIGN OWNED BY %I TO postgres', r);
        EXECUTE format('DROP OWNED BY %I', r);
        EXECUTE format('DROP ROLE %I', r);
    END LOOP;
END $$;
SELECT count(*) AS ex19_roles_left FROM pg_roles WHERE rolname LIKE 'ss\_ex19\_%';
