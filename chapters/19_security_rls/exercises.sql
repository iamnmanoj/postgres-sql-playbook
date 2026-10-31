-- =====================================================================
--  Chapter 19 · Exercises — security, roles & row-level security
--  Prefix your roles with ss_ex19_ and drop them at the end.
-- =====================================================================

-- [E19.01] (easy) Create a NOLOGIN group role ss_ex19_finance and a LOGIN role ss_ex19_priya that is a member of it.
--          List both roles with their login ability.

-- [E19.02] (medium) Give ss_ex19_finance read access to sales.payments and sales.refunds only, then prove with
--          has_table_privilege that ss_ex19_priya can read payments but not orders.

-- [E19.03] (medium) Let ss_ex19_finance see core.users.user_id and email but nothing else; verify with
--          has_column_privilege for email and phone.

-- [E19.04] (hard) Copy core.addresses into playground_19.addresses and enable RLS so that a role
--          ss_ex19_customer only sees rows where user_id = current_setting('app.user_id')::bigint.
--          Test as that role with app.user_id = 42.

-- [E19.05] (hard) Hash the password 'Diwali2025!' with bcrypt (cost 10) and verify a correct and a wrong guess.

-- [E19.06] (easy) Clean up: drop everything you created, including the roles.
