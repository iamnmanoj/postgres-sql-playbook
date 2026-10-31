# Chapter 19 · Security: roles, privileges & row-level security

[← Previous](../18_partitioning/README.md) · [Index](../../README.md) · [Next →](../20_advanced_extras/README.md)

## What you'll learn
- Roles: users vs groups, login attributes, membership and inheritance
- The privilege system: database → schema → table/column/sequence/function, `GRANT`/`REVOKE`, `PUBLIC`, default privileges
- Switching identity with `SET ROLE`, and inspecting grants
- **Row-level security (RLS)** for multi-tenant isolation: policies, `USING` vs `WITH CHECK`, permissive vs restrictive, `FORCE`, `BYPASSRLS`
- Views with `security_invoker`, `SECURITY DEFINER` functions, and password hashing with `pgcrypto`
- Removing roles cleanly

> All demo roles are prefixed `ss_` and **dropped at the end** of [queries.sql](queries.sql), because roles are shared by the whole server, not one database.

## Concepts

### Roles (Q19.01)
Everything is a **role**. A role with `LOGIN` acts as a user, and a role without it acts as a group. `GRANT group TO user` makes the user a member, and with `INHERIT` (the default) the member automatically has the group's privileges.
Best practice: grant privileges to **group roles** (`ss_readonly`), then put people and applications into those groups.
Attributes: `LOGIN`, `PASSWORD`, `VALID UNTIL`, `CONNECTION LIMIT`, `CREATEDB`, `CREATEROLE`, `SUPERUSER`, `BYPASSRLS`, `REPLICATION`.

### The privilege layers (Q19.02–Q19.07)
To read `sales.orders`, a role needs **all** of these:
1. `CONNECT` on the database
2. `USAGE` on schema `sales`
3. `SELECT` on the table, or on the specific columns
| Object | Privileges |
|---|---|
| database | `CONNECT`, `CREATE`, `TEMP` |
| schema | `USAGE`, `CREATE` |
| table / view | `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER` (and per column for SELECT/INSERT/UPDATE/REFERENCES) |
| sequence | `USAGE`, `SELECT`, `UPDATE` |
| function / procedure | `EXECUTE` (granted to `PUBLIC` by default!) |

`GRANT … ON ALL TABLES IN SCHEMA s` covers existing tables, and `ALTER DEFAULT PRIVILEGES` covers tables created later.
Check privileges with `has_table_privilege`, `has_column_privilege` and `has_schema_privilege`, or list grants with `information_schema.role_table_grants` and `aclexplode()`.

### SET ROLE (Q19.08)
`SET ROLE x` switches `current_user`, but `session_user` stays as the role you logged in with. It's ideal for testing permissions. `RESET ROLE` switches back.

### Row-level security (Q19.10–Q19.15)
```sql
ALTER TABLE t ENABLE ROW LEVEL SECURITY;
CREATE POLICY name ON t
    [AS PERMISSIVE | RESTRICTIVE]
    [FOR ALL | SELECT | INSERT | UPDATE | DELETE]
    [TO role, …]
    USING (which existing rows are visible / targetable)
    WITH CHECK (which new or updated rows are allowed);
```
- With RLS enabled and **no policy**, normal users see **nothing** (default deny).
- **Permissive** policies are combined with OR. **Restrictive** policies are combined with AND, on top of them (Q19.13).
- `USING` filters reads and the targets of `UPDATE`/`DELETE`. `WITH CHECK` validates `INSERT` and the new version of updated rows.
- Superusers and roles with `BYPASSRLS` ignore RLS. Table **owners** ignore it too unless you use `FORCE ROW LEVEL SECURITY` (Q19.14).
- **Multi-tenant pattern**: the application connects as one role and runs `SET app.tenant_id = '…'` (or `set_config`) per request, and policies compare against `current_setting('app.tenant_id', true)`. The `true` makes a missing setting return NULL, so no rows match instead of raising an error.
- Views: use `security_invoker = true` (PG15) so the caller's policies apply through the view (Q19.15).

### Secrets (Q19.16)
Never store plain passwords. `crypt(password, gen_salt('bf', cost))` gives bcrypt hashes. To verify, compare `stored = crypt(attempt, stored)`.

### Removing roles (Q19.17)
A role can't be dropped while it owns objects or holds privileges. Run `REASSIGN OWNED BY r TO new_owner; DROP OWNED BY r;` in **every database** where it has privileges, then `DROP ROLE r`.

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `CREATE ROLE`/`CREATE USER`, `LOGIN`/`NOLOGIN`, `PASSWORD`, `VALID UNTIL`, `CONNECTION LIMIT`, `GRANT role TO role` | roles and membership | Q19.01 |
| `GRANT CONNECT`, `GRANT USAGE ON SCHEMA`, `GRANT SELECT ON ALL TABLES IN SCHEMA` | read access | Q19.02 |
| `has_table_privilege()`, `has_schema_privilege()`, `insufficient_privilege` | check privileges | Q19.03 |
| column-level `GRANT`, `has_column_privilege()` | per-column access | Q19.04 |
| `REVOKE`, `PUBLIC` | remove privileges | Q19.05 |
| `ALTER DEFAULT PRIVILEGES` | future objects | Q19.06 |
| `GRANT EXECUTE`, `GRANT USAGE ON SEQUENCE` | functions and sequences | Q19.07 |
| `SET ROLE`, `RESET ROLE`, `current_user`, `session_user` | switch identity | Q19.08 |
| `information_schema.role_table_grants`, `aclexplode()`, `attacl` | inspect grants | Q19.09 |
| `ENABLE ROW LEVEL SECURITY`, `CREATE POLICY … USING`, `current_setting()` | tenant isolation | Q19.10 |
| `WITH CHECK`, `FOR INSERT` | write restrictions | Q19.11 |
| `FOR SELECT/UPDATE … TO role` | per-command policies | Q19.12 |
| `AS RESTRICTIVE` | mandatory extra filter | Q19.13 |
| `FORCE ROW LEVEL SECURITY`, `BYPASSRLS`, `pg_policies` | RLS control and inspection | Q19.14 |
| `security_invoker` view + RLS | RLS through views | Q19.15 |
| `crypt()`, `gen_salt()` | password hashing | Q19.16 |
| `REASSIGN OWNED`, `DROP OWNED`, `DROP ROLE` | clean role removal | Q19.17 |

## Gotchas
- Testing RLS as `postgres` shows **everything**, because superusers bypass RLS. Always test with `SET ROLE`.
- Functions are `EXECUTE`-able by `PUBLIC` by default. Revoke that for sensitive `SECURITY DEFINER` functions.
- `GRANT … ON ALL TABLES` doesn't cover tables created later. Use `ALTER DEFAULT PRIVILEGES`.
- RLS policies run for every row. Keep them simple and indexable (for example `tenant_id = constant`), and index the tenant column.
- A view owned by a superuser bypasses RLS on its base tables unless it has `security_invoker = true`.
- Don't put real passwords in SQL files. These are demo values.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/19_security_rls/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
