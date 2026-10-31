# Chapter 15 · Views & Materialized Views: Virtual & Stored Results

[← Previous](../14_indexes_performance/README.md) · [Index](../../README.md) · [Next →](../16_functions_procedures/README.md)

## What you'll learn
- Views as named, reusable queries, and how the planner expands them
- Rules for changing views, and how dependencies work
- Automatically updatable views and `WITH CHECK OPTION`
- Views as a security boundary: column hiding, `security_barrier`, `security_invoker`
- Recursive views
- Materialized views: creating, indexing, refreshing (also `CONCURRENTLY`) and `WITH NO DATA`

## Concepts

### Views (Q15.01–Q15.04)
A **view** stores a query, not data. Selecting from it runs the underlying query, and the planner **inlines** it, so filters are pushed down and indexes are still used (Q15.02).
Use views to name business concepts (`order_summary`, `daily_kpis`), to hide complex joins, and to give a stable interface over changing tables.
- `CREATE OR REPLACE VIEW` may only **add columns at the end**. It can't drop, rename or retype them, so use `DROP VIEW … ; CREATE VIEW …` for that (Q15.04).
- Objects that depend on a view (other views, functions) block `DROP` unless you use `CASCADE`.

### Updatable views (Q15.05–Q15.07)
A view over **one table** without `DISTINCT`, `GROUP BY`, aggregates, window functions, set operations or `LIMIT` is automatically updatable: `INSERT`, `UPDATE` and `DELETE` pass through to the base table.
`WITH CHECK OPTION` rejects writes that would produce rows the view can't see. `LOCAL` checks only this view's condition, and `CASCADED` (the default) also checks the conditions of underlying views.
For complex views, use `INSTEAD OF` triggers (ch17).

### Security with views (Q15.08–Q15.09)
- Hide sensitive columns and rows, then `GRANT SELECT` on the view instead of the table (ch19).
- `security_barrier`: functions in the user's `WHERE` can't run before the view's own filter, so they can't leak hidden rows.
- By default a view reads base tables with the **owner's** privileges. `security_invoker = true` (PG15) uses the **caller's** privileges and RLS policies.

### Recursive views (Q15.10)
`CREATE RECURSIVE VIEW name (cols) AS <anchor> UNION ALL <recursive part referencing name>` is shorthand for a view over `WITH RECURSIVE`.

### Materialized views (Q15.11–Q15.16)
A **materialized view** stores the result like a table. It's fast to read, but **stale** until refreshed.
| Command | Behaviour |
|---|---|
| `CREATE MATERIALIZED VIEW … AS …` | run the query now and store the result |
| `… WITH NO DATA` | create it empty; reading it raises an error until the first refresh |
| `REFRESH MATERIALIZED VIEW mv` | recompute; **blocks readers** while it runs |
| `REFRESH MATERIALIZED VIEW CONCURRENTLY mv` | readers keep working; needs a **UNIQUE index**; slower |
| `CREATE INDEX ON mv (…)` | index it like a table |

Refresh with a scheduler (cron, `pg_cron`, the application) or after batch loads. Include `now() AS refreshed_at` so readers know how fresh the data is.
**View vs materialized view vs table**: a view is always current but costs a query each time, a matview is fast but stale, and a summary table maintained by triggers is fast and current but more complex (ch17).

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `CREATE [OR REPLACE] VIEW` | define a view | Q15.01 |
| `pg_get_viewdef()`, view expansion | inspect a view, see it inlined | Q15.02 |
| view on view | layered reporting | Q15.03 |
| OR REPLACE limits, `DROP VIEW`, dependencies | changing views | Q15.04 |
| updatable view | write through a view | Q15.05 |
| `WITH [LOCAL\|CASCADED] CHECK OPTION` | restrict writes | Q15.06 |
| `information_schema.views` | updatability metadata | Q15.07 |
| `security_barrier` | leak-proof filtering | Q15.08 |
| `security_invoker`, `ALTER VIEW … SET` | caller's permissions (PG15) | Q15.09 |
| `CREATE RECURSIVE VIEW` | recursive view | Q15.10 |
| `CREATE MATERIALIZED VIEW` | stored result | Q15.11 |
| index on a materialized view | fast lookups | Q15.12 |
| `REFRESH MATERIALIZED VIEW` | recompute | Q15.13 |
| `REFRESH … CONCURRENTLY` | non-blocking refresh | Q15.14 |
| `WITH NO DATA`, `pg_matviews.ispopulated` | deferred population | Q15.15 |
| `pg_views`, `pg_matviews`, `pg_depend`, `pg_rewrite` | view catalog and dependencies | Q15.16 |

## Gotchas
- `SELECT *` in a view is expanded **when the view is created**. Columns added to the table later don't appear.
- A view doesn't make a slow query fast. A materialized view or an index does.
- `REFRESH … CONCURRENTLY` fails without a unique index that covers **all rows**, so the index can't be partial.
- Materialized views aren't refreshed automatically when base tables change.
- Changing a column type in a base table fails if a view depends on it. Drop and recreate the view in the same transaction.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/15_views_materialized/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
