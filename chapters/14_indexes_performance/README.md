# Chapter 14 · Indexes & performance

[← Previous](../13_full_text_search/README.md) · [Index](../../README.md) · [Next →](../15_views_materialized/README.md)

## What you'll learn
- Reading query plans with `EXPLAIN` and `EXPLAIN ANALYZE`
- B-tree indexes: single-column, multi-column (and why column order matters), covering (`INCLUDE`), partial, expression, unique
- GIN, GiST, BRIN and hash indexes, and when to use each
- Index maintenance: `CONCURRENTLY`, `REINDEX`, unindexed foreign keys, unused indexes
- Statistics, `ANALYZE`, extended statistics, `VACUUM` and table bloat
- Tuning patterns: sargable predicates, keyset pagination, `work_mem`, `pg_stat_statements`, parallel query

## How to read EXPLAIN

```
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_number, placed_at FROM sales.orders WHERE user_id = 42 ORDER BY placed_at DESC LIMIT 10;

 Limit  (cost=0.29..39.12 rows=10 width=27) (actual time=0.020..0.031 rows=10 loops=1)
   Buffers: shared hit=13
   ->  Index Scan using ix14_orders_user_placed on orders  (cost=0.29..63.41 rows=16 width=27)
                                                          (actual time=0.019..0.029 rows=10 loops=1)
         Index Cond: (user_id = 42)
         Buffers: shared hit=13
 Planning Time: 0.120 ms
 Execution Time: 0.050 ms
```
- **Read it inside out**: the most indented node runs first and feeds its parent.
- `cost=startup..total` are planner estimates in arbitrary units. Only compare them within the same query.
- `rows=` (estimate) vs `actual … rows=`: a **large mismatch** is the #1 cause of bad plans. Fix it with `ANALYZE` or extended statistics (Q14.20).
- `loops=N`: the node ran N times (inner side of a nested loop), so multiply the time by loops.
- `Buffers: shared hit` means pages came from cache, and `read` means they came from disk.
- `Index Cond` uses the index. `Filter` checks rows *after* fetching them, so `Rows Removed by Filter` is wasted work.

### Plan nodes you'll meet
| Node | Meaning |
|---|---|
| Seq Scan | read the whole table (fine for small tables or large fractions of rows) |
| Index Scan | walk the index, fetch each matching row from the table |
| Index Only Scan | answer from the index alone (needs all columns in the index plus a fresh visibility map) |
| Bitmap Index/Heap Scan | collect matching row locations, then read the pages in physical order. Good for medium selectivity, and can combine indexes (BitmapAnd/Or) |
| Nested Loop | for each outer row, look up the inner side. Good when outer is small and inner is indexed |
| Hash Join | build a hash table of one side, then probe it. Good for big unsorted equi-joins |
| Merge Join | merge two sorted inputs |
| Sort / Incremental Sort / top-N heapsort | ordering. Watch `Sort Method: external merge Disk`, which means work_mem was too small |
| HashAggregate / GroupAggregate | `GROUP BY` |
| Gather / Parallel … | parallel workers |
| Memoize | caches inner-side lookups of a nested loop (PG14) |

## Concepts

### B-tree, the default index (Q14.05–Q14.11)
- It supports `=`, `<`, `>`, `BETWEEN`, `IN`, `IS NULL`, prefix `LIKE 'abc%'` (with C collation or `text_pattern_ops`), and `ORDER BY`.
- **Multi-column**: it can serve queries on the *leftmost* columns. Put equality columns first, then range or sort columns (Q14.06).
- **Covering** (`INCLUDE`) adds payload columns for index-only scans (Q14.07).
- **Partial** (`WHERE …`) indexes only the rows you query. It's small and fast, which is ideal for "open orders" (Q14.08).
- **Expression** indexes the result of a function, such as `lower(x)`. Queries must use the **same** expression (Q14.09).
- **Unique** indexes enforce rules, and a partial unique index gives you "unique among active rows" (Q14.10).

### Other index types (Q14.12–Q14.16)
| Type | Best for | ShopSphere example |
|---|---|---|
| **GIN** | "contains" queries on composite values: jsonb, arrays, tsvector, trigrams | `metadata @> …`, `tags @> …` |
| **GiST** | ranges, geometry, nearest-neighbour, exclusion constraints | `valid_during @> now()`, payout overlap |
| **BRIN** | huge, naturally ordered tables (time series). The index is tiny | `shipment_events.occurred_at` |
| **Hash** | equality only, sometimes smaller than B-tree | `provider_ref = …` |
| SP-GiST | partitioned search spaces (IP ranges, quad-trees) | — |

`jsonb_ops` (the default) supports `@>`, `?`, `?|` and `?&`. `jsonb_path_ops` supports only `@>`, but it's smaller and faster.

### Maintenance (Q14.17–Q14.19)
- `CREATE INDEX CONCURRENTLY` builds without blocking writes, but it can't run inside a transaction and leaves an `INVALID` index if it fails.
- **PostgreSQL doesn't index foreign keys automatically.** Q14.18 finds FKs that have no supporting index.
- `pg_stat_user_indexes.idx_scan = 0` points to drop candidates. Never drop PK or UNIQUE indexes, though.
- Every index slows down `INSERT`/`UPDATE`/`DELETE` and uses disk, so index for real queries only.

### Statistics and VACUUM (Q14.20–Q14.22)
- `ANALYZE` samples tables into `pg_stats` (MCVs, histograms, n_distinct). The planner assumes columns are **independent**. `CREATE STATISTICS (dependencies | ndistinct | mcv)` teaches it about correlations (city → state).
- **MVCC leaves dead tuples** after `UPDATE` and `DELETE`. `VACUUM` makes their space reusable and updates the visibility map. Autovacuum does this automatically, so watch `n_dead_tup` and `last_autovacuum`.
- `VACUUM FULL` rewrites the table to shrink it, but it takes an exclusive lock. Avoid it on busy tables.

### Tuning patterns (Q14.23–Q14.27)
- **Sargable predicates**: don't wrap the indexed column in a function (`placed_at::date = …`). Compare the raw column with a range instead.
- **Keyset pagination** beats deep `OFFSET`.
- `work_mem` is the memory per sort or hash node. Too little spills to disk.
- `pg_stat_statements` shows the queries that use the most total time across the whole system. Start tuning there.
- **Parallel query** splits big scans and aggregates across workers.

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `EXPLAIN` | show the estimated plan | Q14.01 |
| `EXPLAIN (ANALYZE, BUFFERS)` | run the query and show actuals | Q14.02 |
| `EXPLAIN (FORMAT JSON, VERBOSE, SETTINGS, SUMMARY)` | detailed or machine-readable plan | Q14.03 |
| Nested Loop / Hash Join / Merge Join, `enable_*` | join algorithms | Q14.04 |
| `CREATE INDEX` | B-tree index | Q14.05 |
| composite index, leftmost prefix | multi-column index | Q14.06 |
| `INCLUDE`, Index Only Scan | covering index | Q14.07 |
| partial index `WHERE` | index a subset | Q14.08 |
| expression index | index a function result | Q14.09 |
| `CREATE UNIQUE INDEX` | uniqueness via index | Q14.10 |
| index order for `ORDER BY … LIMIT` | avoid sorts | Q14.11 |
| `USING gin`, `jsonb_path_ops` | JSONB index | Q14.12 |
| GIN on arrays | array index | Q14.13 |
| `USING gist` | range index | Q14.14 |
| `USING brin`, `pages_per_range` | block-range index | Q14.15 |
| `USING hash` | hash index | Q14.16 |
| `CONCURRENTLY`, `REINDEX` | online index maintenance | Q14.17 |
| unindexed FK query | FK index audit | Q14.18 |
| `pg_stat_user_indexes` | index usage | Q14.19 |
| `pg_stats`, `CREATE STATISTICS` | planner statistics | Q14.20 |
| `VACUUM`, `n_dead_tup`, autovacuum | dead-tuple cleanup | Q14.21 |
| `pg_relation_size()`, `pg_indexes_size()`, `pg_total_relation_size()`, `pg_database_size()` | sizes | Q14.22 |
| sargable rewrite | make predicates indexable | Q14.23 |
| OFFSET vs keyset | pagination cost | Q14.24 |
| `work_mem` | sort and hash memory | Q14.25 |
| `pg_stat_statements` | top queries | Q14.26 |
| parallel query, `Gather` | multi-core execution | Q14.27 |

## Gotchas
- On small tables a Seq Scan **is** the best plan. Don't panic about it, and don't "fix" it with `enable_seqscan = off` in production.
- `EXPLAIN ANALYZE` executes the statement, so wrap `UPDATE` and `DELETE` in `BEGIN … ROLLBACK`.
- `LIKE '%x'` and `ILIKE` can't use a B-tree index. Use trigram GIN (ch13).
- An index on `(a, b)` doesn't help `WHERE b = …`.
- Implicit casts can stop index use, for example comparing a `bigint` column with a `numeric` literal.
- Too many indexes mean slow writes and more bloat.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/14_indexes_performance/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
