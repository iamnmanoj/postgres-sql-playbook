# Chapter 20 · Advanced extras

[← Previous](../19_security_rls/README.md) · [Index](../../README.md) · [Next → Tips](../../TIPS.md)

## What you'll learn
- Range and multirange types: overlap, containment, gaps, intersections, exclusion constraints
- `LISTEN`/`NOTIFY` messaging
- Sequences in depth, and `TABLESAMPLE`
- Reading the system catalogs (`pg_class`, `pg_attribute`, `pg_constraint`, `pg_depend`, `pg_settings`…)
- Collations (natural sort, case-insensitive)
- Row values, SQL cursors and prepared statements
- psql power tools: `\gset`, `\gexec`, `\crosstabview`, `\watch`
- Extensions: `tablefunc` (crosstab), `hstore`, `postgres_fdw`
- Backups with `pg_dump`/`pg_restore`

> [queries.sql](queries.sql) uses psql meta-commands (`\gset`, `\gexec`, `\crosstabview`), so run it with `psql`.

## Concepts

### Ranges and multiranges (Q20.01–Q20.04)
Range types: `int4range`, `int8range`, `numrange`, `daterange`, `tsrange`, `tstzrange`. Bounds are written `[` (inclusive) and `)` (exclusive), and an omitted bound means infinity.
| Operator / function | Meaning |
|---|---|
| `@>` / `<@` | contains / is contained in (a range or an element) |
| `&&` | overlaps |
| `-\|-` | adjacent |
| `*`, `+`, `-` | intersection, union, difference |
| `lower()`, `upper()`, `isempty()`, `upper_inf()` | inspect bounds |
| `range_agg()` → **multirange** (PG14) | union of many ranges, which may have gaps |
| `range_intersect_agg()` | intersection of many ranges |

Multiranges make **gap analysis** trivial: `wanted_period − covered_periods` (Q20.02).
`EXCLUDE USING gist (seller_id WITH =, period WITH &&)` guarantees no overlapping periods per seller. It needs `btree_gist` for the `=` part.

### LISTEN / NOTIFY (Q20.05)
These are lightweight pub/sub messages between sessions. Notifications are delivered at `COMMIT` and are deduplicated within a transaction, with a payload of up to 8000 bytes.
Typical uses: cache invalidation, waking up workers, and live dashboards. Messages aren't stored, so a listener that isn't connected misses them.

### Sequences (Q20.06)
`CACHE n` speeds things up by pre-allocating values per session (expect gaps), `CYCLE` wraps around, and `pg_get_serial_sequence` finds the sequence behind an identity column.
**Sequences never roll back**, so gaps in ids are normal.

### TABLESAMPLE (Q20.07)
`SYSTEM (p)` samples whole pages, which is very fast but clustered. `BERNOULLI (p)` samples individual rows, which is more uniform. `REPEATABLE (seed)` makes the sample reproducible.

### System catalogs (Q20.08–Q20.11)
`pg_catalog` holds PostgreSQL's own tables: `pg_class` (relations), `pg_attribute` (columns), `pg_namespace` (schemas), `pg_constraint`, `pg_index`, `pg_depend`, `pg_proc` and `pg_settings`.
`information_schema` is the portable, SQL-standard view of the same data, but it's slower and less detailed.
Casts such as `::regclass`, `::regtype`, `::regnamespace` and `::regprocedure` translate between names and OIDs.

### Collations (Q20.12)
A collation decides sort order and equality for text. ICU collations support natural number ordering (`kn`) and case-insensitive comparison (`deterministic = false`).

### Row values, cursors, prepared statements (Q20.13–Q20.15)
- `t.*` is the whole row as a value: compare whole rows with `IS DISTINCT FROM`, or convert them with `row_to_json(t)`.
- **Cursors** (`DECLARE … CURSOR`, `FETCH`, `MOVE`, `CLOSE`) stream large results inside a transaction. `WITH HOLD` keeps a cursor open after commit, and `SCROLL` allows moving backwards.
- **Prepared statements** are parsed and planned once and executed many times. Application drivers use them through parameters (`$1`), which is also how you avoid SQL injection.

### psql power tools (Q20.16)
| Command | Effect |
|---|---|
| `\gset [prefix]` | store the result columns in psql variables (`:var`, `:'var'` quoted) |
| `\gexec` | run every value in the result as a SQL statement |
| `\crosstabview` | pivot a 3-column result into a grid |
| `\watch 5` | re-run the last query every 5 seconds (live dashboard) |
| `\if`, `\elif`, `\else`, `\endif` | conditional scripts |

### Extensions (Q20.17–Q20.19)
- `tablefunc.crosstab(source_sql, categories_sql)` pivots in SQL.
- `hstore` is a flat key/value type that predates `jsonb`. Prefer `jsonb` for new work.
- `postgres_fdw` queries another PostgreSQL server through foreign tables, and pushes `WHERE` clauses down to it. `dblink` (ch11) runs ad-hoc remote SQL.

## Backups and restores (run in a shell, not in psql)
```bash
# logical backup of one database (custom format, compressed, restorable selectively)
docker compose exec -T db pg_dump -U postgres -Fc shopsphere > shopsphere.dump
# schema only / data only / one table
docker compose exec -T db pg_dump -U postgres --schema-only shopsphere > schema.sql
docker compose exec -T db pg_dump -U postgres -t sales.orders --data-only shopsphere > orders.sql
# restore into a new database
docker compose exec -T db createdb -U postgres shopsphere_restored
docker compose exec -T db pg_restore -U postgres -d shopsphere_restored --jobs 4 < shopsphere.dump
# all databases + roles
docker compose exec -T db pg_dumpall -U postgres > cluster.sql
```
For production you'd also use physical backups (`pg_basebackup`), WAL archiving and point-in-time recovery (pgBackRest, Barman), plus streaming replication for high availability.

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `daterange()`, `tstzrange()`, `lower()`, `upper()`, `@>`, `&&`, `-\|-`, `*`, `isempty()`, `upper_inf()` | range basics | Q20.01 |
| `range_agg()`, multirange, `datemultirange()`, `unnest(multirange)` | union and gaps | Q20.02 |
| `range_intersect_agg()` | common window | Q20.03 |
| `EXCLUDE USING gist`, `exclusion_violation` | no-overlap rule | Q20.04 |
| `LISTEN`, `NOTIFY`, `pg_notify()`, `UNLISTEN` | pub/sub | Q20.05 |
| `CREATE SEQUENCE … CYCLE/CACHE`, `pg_get_serial_sequence()`, `pg_sequences`, `ALTER SEQUENCE … RESTART` | sequences | Q20.06 |
| `TABLESAMPLE SYSTEM/BERNOULLI … REPEATABLE` | sampling | Q20.07 |
| `pg_class`, `pg_attribute`, `format_type()` | relation metadata | Q20.08 |
| `pg_constraint`, `pg_get_constraintdef()`, `information_schema.table_constraints` | constraints | Q20.09 |
| `pg_depend`, `pg_describe_object()` | dependencies | Q20.10 |
| `pg_settings`, `pg_extension`, `pg_available_extensions` | configuration | Q20.11 |
| `COLLATE`, `CREATE COLLATION` (ICU) | sorting rules | Q20.12 |
| row values `t.*`, `ROW()`, `(row).field` | whole-row operations | Q20.13 |
| `DECLARE … CURSOR`, `FETCH`, `MOVE`, `CLOSE`, `SCROLL` | SQL cursors | Q20.14 |
| `PREPARE`, `EXECUTE`, `DEALLOCATE`, `pg_prepared_statements` | prepared statements | Q20.15 |
| `\gset`, `\gexec`, `\crosstabview` | psql tools | Q20.16 |
| `crosstab()` | SQL pivot | Q20.17 |
| `hstore` | key/value type | Q20.18 |
| `postgres_fdw`, `CREATE SERVER`, `USER MAPPING`, `IMPORT FOREIGN SCHEMA` | federated queries | Q20.19 |
| `pg_postmaster_start_time()`, `inet_server_port()` | server information | Q20.20 |

## Gotchas
- Mixing inclusive and exclusive bounds causes off-by-one bugs. Stick to `[)` (the default) for time.
- `NOTIFY` inside a transaction that rolls back is never delivered.
- `TABLESAMPLE SYSTEM` on small tables can return 0 rows.
- Catalog queries are version-specific, so prefer `information_schema` for portable tools.
- Non-deterministic collations can't be used with `LIKE` (before PG18) or some index types.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/20_advanced_extras/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql). Finish with [TIPS.md](../../TIPS.md).
