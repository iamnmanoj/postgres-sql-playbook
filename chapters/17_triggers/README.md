# Chapter 17 · Triggers: Automatic Actions on Data Changes

[← Previous](../16_functions_procedures/README.md) · [Index](../../README.md) · [Next →](../18_partitioning/README.md)

## What you'll learn
- Trigger functions and the special variables `NEW`, `OLD`, `TG_OP`, `TG_TABLE_NAME`, `TG_ARGV`…
- `BEFORE` vs `AFTER`, `FOR EACH ROW` vs `FOR EACH STATEMENT`, `UPDATE OF col`, `WHEN (…)`
- Real uses: `updated_at`, data normalisation, price history, status history, generic audit logging
- Transition tables for set-based statement triggers
- `INSTEAD OF` triggers on views, deferred **constraint triggers**, `TRUNCATE` triggers, **event triggers** for DDL
- Disabling triggers, firing order, recursion guards

> **Installed by this chapter (and kept):** `set_updated_at` on users/products/orders, `normalise_seller` and `audit` on sellers, `audit` on coupons, `log_price_change` on products, `order_status_history` on orders, `stock_batch_summary` on inventory, `no_truncate` on audit_log, and the `app.cart_lines` view with its `INSTEAD OF` trigger. Demo triggers are dropped at the end.

## Concepts

### Anatomy
```sql
CREATE FUNCTION app.trg_x() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN … RETURN NEW; END $$;

CREATE [OR REPLACE] [CONSTRAINT] TRIGGER name
  { BEFORE | AFTER | INSTEAD OF } { INSERT | UPDATE [OF col, …] | DELETE | TRUNCATE } [OR …]
  ON table
  [REFERENCING OLD TABLE AS o NEW TABLE AS n]
  [FOR EACH { ROW | STATEMENT }]
  [WHEN (condition on OLD/NEW)]
  EXECUTE FUNCTION app.trg_x(args…);
```

### What to return
| Trigger | Return value |
|---|---|
| `BEFORE … FOR EACH ROW` | `NEW` (possibly modified) to proceed, or `NULL` to **silently skip** the row. For DELETE, return `OLD` |
| `AFTER … FOR EACH ROW` | ignored (use `NULL`) |
| `FOR EACH STATEMENT` | ignored |
| `INSTEAD OF` (views) | `NEW` to report the row as processed, `NULL` to skip |

### Special variables
`NEW`/`OLD` (row values; `OLD` is NULL on INSERT and `NEW` is NULL on DELETE), `TG_OP` (`INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`), `TG_WHEN`, `TG_LEVEL`, `TG_NAME`, `TG_TABLE_SCHEMA`, `TG_TABLE_NAME`, `TG_ARGV[]`, `TG_NARGS`.

### BEFORE vs AFTER
- **BEFORE**: change or validate the row before it's written (defaults, normalisation, derived values). Cheap.
- **AFTER**: react to a change that has definitely happened (audit, history, notifications, other tables). The row has passed constraints.
- **Statement-level with transition tables** (Q17.07): one call per statement that sees *all* changed rows. It's far faster for bulk operations than row triggers.

### Special kinds
- `INSTEAD OF` on a view makes complex views writable (Q17.09).
- `CREATE CONSTRAINT TRIGGER … DEFERRABLE INITIALLY DEFERRED` checks multi-row business rules at **commit** (Q17.10).
- **Event triggers** (`ddl_command_start`, `ddl_command_end`, `sql_drop`, `table_rewrite`, `login` in PG17) fire on DDL, not data. Use them for change logs and policy enforcement (Q17.13).

### Firing order and control
Triggers of the same timing and level fire in **alphabetical order by name** (Q17.12).
`ALTER TABLE … DISABLE/ENABLE TRIGGER name|ALL|USER`, or `SET session_replication_role = replica` for bulk loads (superuser only), switch triggers off.
`pg_trigger_depth()` helps prevent infinite trigger recursion.

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `RETURNS trigger`, `NEW`, `BEFORE UPDATE`, `FOR EACH ROW`, `CREATE OR REPLACE TRIGGER` | basic row trigger | Q17.01 |
| `BEFORE INSERT OR UPDATE`, `TG_OP`, validation | normalise and validate | Q17.02 |
| `AFTER UPDATE OF col`, `WHEN (…)`, `OLD` | conditional trigger | Q17.03 |
| status-history trigger | state machine log | Q17.04 |
| `TG_TABLE_SCHEMA`, `TG_TABLE_NAME`, `TG_ARGV`, `to_jsonb(OLD/NEW)` | generic audit | Q17.05 |
| audit diff via `jsonb_each()` | changed-fields report | Q17.06 |
| `FOR EACH STATEMENT`, `REFERENCING OLD/NEW TABLE` | transition tables | Q17.07 |
| `BEFORE TRUNCATE`, `TG_WHEN`, `TG_LEVEL` | truncate guard | Q17.08 |
| `INSTEAD OF INSERT` on a view | writable complex view | Q17.09 |
| `CREATE CONSTRAINT TRIGGER … DEFERRABLE` | commit-time rule | Q17.10 |
| `DISABLE TRIGGER`, `ENABLE TRIGGER` | switch triggers off and on | Q17.11 |
| firing order, `pg_trigger_depth()` | ordering and recursion | Q17.12 |
| `CREATE EVENT TRIGGER`, `pg_event_trigger_ddl_commands()` | DDL logging | Q17.13 |
| `information_schema.triggers`, `pg_trigger`, `pg_event_trigger`, `pg_get_triggerdef()` | list triggers | Q17.14 |

## Gotchas
- Triggers are **invisible** to whoever reads the application code. Document them and keep them small.
- Row-level triggers run once per row, so a 1-million-row `UPDATE` makes 1 million calls. Prefer statement-level triggers with transition tables.
- A `BEFORE` trigger that returns `NULL` silently drops the row, which is a classic bug.
- `UPDATE OF col` fires when the column is in the `SET` list even if its value didn't change. Add `WHEN (OLD.col IS DISTINCT FROM NEW.col)`.
- `TRUNCATE` doesn't fire `DELETE` triggers.
- Triggers that update the same table can recurse. Guard them with `WHEN` or `pg_trigger_depth()`.
- DDL is transactional in PostgreSQL, so you can create a trigger, test it, and `ROLLBACK` (solutions.sql does exactly that).

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/17_triggers/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
