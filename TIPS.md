# Tips: common mistakes, performance and design

A checklist distilled from all 20 chapters. Each tip links to the chapter that demonstrates it.

## 1. Correctness traps
| ❌ Mistake | ✅ Do instead | Chapter |
|---|---|---|
| `WHERE col = NULL` | `WHERE col IS NULL` | [03](chapters/03_select_filtering/README.md) |
| `x NOT IN (SELECT y …)` where `y` can be NULL, which returns **no rows** | `NOT EXISTS (SELECT 1 … WHERE y = x)` | [07](chapters/07_subqueries_set_ops/README.md) |
| `'a' \|\| NULL` silently becomes NULL | `concat()`, `concat_ws()` or `COALESCE` | [04](chapters/04_builtin_functions/README.md) |
| `count(*) * 100 / total`: integer division | multiply by `100.0` or cast to `numeric` | [04](chapters/04_builtin_functions/README.md) |
| `float`/`real` for money | `numeric(12,2)` | [01](chapters/01_ddl_schema/README.md) |
| `timestamp` for real events | `timestamptz` | [01](chapters/01_ddl_schema/README.md), [04](chapters/04_builtin_functions/README.md) |
| `BETWEEN '2025-01-01' AND '2025-01-31'` on timestamps | half-open range: `>= '2025-01-01' AND < '2025-02-01'` | [03](chapters/03_select_filtering/README.md) |
| filter on the optional table in `WHERE` after a `LEFT JOIN` | put it in the `ON` clause | [06](chapters/06_joins/README.md) |
| summing after joining two one-to-many tables (fan-out) | aggregate each side first, then join | [06](chapters/06_joins/README.md) |
| `LIMIT` without `ORDER BY` | always order; add a unique tiebreaker | [03](chapters/03_select_filtering/README.md), [09](chapters/09_window_functions/README.md) |
| `last_value()` with the default window frame | `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` | [09](chapters/09_window_functions/README.md) |
| read-then-write in READ COMMITTED (lost updates) | `UPDATE … SET x = x + 1`, or `SELECT … FOR UPDATE` | [11](chapters/11_transactions_locking/README.md) |
| no retry for REPEATABLE READ / SERIALIZABLE | retry the whole transaction on SQLSTATE `40001` | [11](chapters/11_transactions_locking/README.md) |
| `->>` result compared as a number | cast: `(doc->>'qty')::int > 5` | [12](chapters/12_jsonb_arrays/README.md) |
| `to_tsquery(user_input)` raises errors on odd input | `websearch_to_tsquery(user_input)` | [13](chapters/13_full_text_search/README.md) |
| testing RLS as the superuser | `SET ROLE app_role` first | [19](chapters/19_security_rls/README.md) |

## 2. Performance
1. **Measure first**: use `pg_stat_statements` to find the expensive queries, then `EXPLAIN (ANALYZE, BUFFERS)` to see why ([14](chapters/14_indexes_performance/README.md)).
2. **Compare estimated and actual rows.** Big differences point to stale or missing statistics, so run `ANALYZE` or `CREATE STATISTICS` ([14](chapters/14_indexes_performance/README.md)).
3. **Index what you filter, join and sort on.** Put equality columns first in composite indexes. Use partial indexes for "hot" subsets and `INCLUDE` for index-only scans.
4. **Index your foreign keys.** PostgreSQL doesn't do it for you, and deletes on the parent scan the child otherwise ([14](chapters/14_indexes_performance/README.md)).
5. **Keep predicates sargable**: `placed_at >= X AND placed_at < Y`, not `placed_at::date = …` or `extract(year …) = …`.
6. **Use keyset pagination** instead of deep `OFFSET` ([03](chapters/03_select_filtering/README.md), [14](chapters/14_indexes_performance/README.md)).
7. **Prefer set-based SQL** to row-by-row loops in PL/pgSQL or application code ([16](chapters/16_functions_procedures/README.md)).
8. **Use `EXISTS` for "is there any"** questions, because it stops at the first match.
9. **Use `UNION ALL` unless you need de-duplication.**
10. **Use the right index type**: GIN for jsonb, arrays, FTS and trigrams; GiST for ranges; BRIN for huge append-only time series ([14](chapters/14_indexes_performance/README.md)).
11. **Watch out for bloat.** Mass `UPDATE`/`DELETE` leaves dead tuples. Let autovacuum keep up, and drop partitions instead of deleting old data ([14](chapters/14_indexes_performance/README.md), [18](chapters/18_partitioning/README.md)).
12. **Precompute expensive dashboards** with materialized views and `REFRESH … CONCURRENTLY` ([15](chapters/15_views_materialized/README.md)).
13. **Batch large writes** with procedures that `COMMIT` per batch ([16](chapters/16_functions_procedures/README.md)).
14. **Increase `work_mem` per session** for big sorts and hashes. Don't raise it globally ([14](chapters/14_indexes_performance/README.md)).

## 3. Concurrency and operations
- Keep transactions **short**, and never leave sessions "idle in transaction". Set `idle_in_transaction_session_timeout`.
- Lock rows in a **consistent order** to avoid deadlocks.
- Use `FOR UPDATE SKIP LOCKED` for job queues and advisory locks for singleton jobs ([11](chapters/11_transactions_locking/README.md)).
- Set `lock_timeout` before running migrations, so DDL doesn't queue every other query behind it.
- Use `CREATE INDEX CONCURRENTLY` and `DETACH PARTITION … CONCURRENTLY` on live systems.
- Back up with `pg_dump -Fc` (logical) and use physical backups with WAL archiving for point-in-time recovery ([20](chapters/20_advanced_extras/README.md)).

## 4. Schema design
- Use `bigint GENERATED ALWAYS AS IDENTITY` primary keys, plus a `uuid` public id if ids are exposed to clients ([01](chapters/01_ddl_schema/README.md)).
- Put **constraints in the database** (NOT NULL, CHECK, FK, UNIQUE, EXCLUDE). It's the last line of defence for data quality.
- Use ENUMs for small, stable sets. Use lookup tables when values change often or carry extra attributes.
- Use JSONB for truly flexible attributes. Promote fields you filter or join on often to real columns ([12](chapters/12_jsonb_arrays/README.md)).
- Use range types and `EXCLUDE` constraints for bookings, validity windows and payout periods ([20](chapters/20_advanced_extras/README.md)).
- Partition only big tables with a natural key (usually time) that queries filter on ([18](chapters/18_partitioning/README.md)).
- Denormalise deliberately and keep the copies in sync with generated columns or triggers ([01](chapters/01_ddl_schema/README.md), [17](chapters/17_triggers/README.md)).

## 5. Security
- Apply **least privilege** with group roles, and grant on schemas, tables and columns ([19](chapters/19_security_rls/README.md)).
- Use RLS with `current_setting('app.tenant_id', true)` for multi-tenant data, and test with `SET ROLE`.
- `SECURITY DEFINER` functions need `SET search_path` and `REVOKE EXECUTE … FROM PUBLIC` ([16](chapters/16_functions_procedures/README.md)).
- Use parameterised queries or `format('%I', …)` + `USING`. Never concatenate input into SQL ([16](chapters/16_functions_procedures/README.md)).
- Store passwords as hashes (`crypt()` + `gen_salt('bf')`), never in plain text.

## 6. Where to go next
- The official docs: <https://www.postgresql.org/docs/current/>, especially the *SQL Commands* reference and *Performance Tips*.
- Practice sites: pgexercises.com, and the Pagila sample database.
- Tools: `pg_partman` (partition automation), `pg_cron` (scheduling), `pgBackRest` (backups), `pgBadger` (log analysis), `auto_explain`.
