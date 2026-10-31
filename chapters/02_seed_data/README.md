# Chapter 02 · Getting data in: INSERT, generate_series, COPY

[← Previous](../01_ddl_schema/README.md) · [Index](../../README.md) · [Next →](../03_select_filtering/README.md)

## What you'll learn
- Every form of `INSERT`: single row, multi-row, defaults, `INSERT … SELECT`, `RETURNING`, `OVERRIDING SYSTEM VALUE`
- `VALUES` as a stand-alone table expression
- Generating test data with `generate_series`, `random`, `setseed`, `random_normal`, `md5` and `gen_random_uuid`
- Bulk loading and exporting with `COPY` and psql's `\copy`
- How [seed.sql](seed.sql) builds the realistic ShopSphere data set

## Concepts

### INSERT (Q02.01–Q02.08)
```sql
INSERT INTO table (col1, col2) VALUES (v1, v2), (v3, v4) RETURNING id;
```
- **List the columns.** Any column you leave out gets its `DEFAULT`, or NULL if it has none (Q02.02).
- `DEFAULT` used as a value means "use the column default". `DEFAULT VALUES` inserts a row made only of defaults (Q02.03).
- **Multi-row `VALUES`** is much faster than many one-row statements (Q02.04).
- **`RETURNING`** hands back generated ids or timestamps without a second query (Q02.05).
- **`INSERT … SELECT`** copies the result of any query (Q02.06).
- `OVERRIDING SYSTEM VALUE` lets you write into a `GENERATED ALWAYS` identity column, which is useful for migrations (Q02.07).
- Wrapping experiments in `BEGIN … ROLLBACK` lets you try changes on real tables safely (Q02.08).

> `INSERT … ON CONFLICT` (upsert) is covered in [chapter 10](../10_dml_upsert_merge/README.md).

### VALUES as a table (Q02.09)
`(VALUES (…), (…)) AS t(col_a, col_b)` builds a small inline table. It's handy for lookups and for joining against a fixed list.

### Generating data (Q02.10–Q02.14)
| Function | Produces |
|---|---|
| `generate_series(start, stop [, step])` | one row per number, date or timestamp |
| `random()` | a float in [0, 1). `random(min, max)` gives an integer in a range (PG17) |
| `setseed(x)` | makes `random()` repeatable for the session |
| `random_normal(mean, stddev)` | values on a bell curve (PG16) |
| `md5(text)` | a 32-character hex hash, handy for fake codes |
| `gen_random_uuid()` | a random UUID v4 |

**How [seed.sql](seed.sql) works.** It runs six include files ([seed/](seed/)) in order:
1. **[00_lookups.sql](seed/00_lookups.sql)**: roles, 8 warehouses, 30 fictional brands, and the 44-node category tree. The tree is inserted level by level in a `DO` loop until `NOT FOUND`. `TEMP` tables hold generator settings such as product nouns, features, colours and price ranges per category.
2. **[01_users_sellers.sql](seed/01_users_sellers.sql)**: 5,000 users built from name arrays, with `created_at` spread over 2 years and about 15% NULL phones. ~20% are referred by an earlier user. Each user has 1–3 addresses with exactly one default, and every 25th user owns a store.
3. **[02_catalog_inventory.sql](seed/02_catalog_inventory.sql)**: 3,000 products built with chained CTEs (`picks → shaped → named`). Sellers are skewed with `power(random(), 1.5)`, so a few sellers own many products. Each product kind gets its own JSONB `attributes` and its own variants (sizes for fashion, colours and storage for electronics). Inventory is spread over 1–3 warehouses.
4. **[03_coupons_orders.sql](seed/03_coupons_orders.sql)**: coupons with time ranges relative to `now()`, then 30,000 orders. Order status depends on how old the order is. Items are skewed with `power(random(), 2)`, so a few products are bestsellers. Totals are computed with `UPDATE … FROM`, coupons are applied with `LATERAL`, and a status history is replayed with `unnest … WITH ORDINALITY`.
5. **[04_payments_shipping.sql](seed/04_payments_shipping.sql)**: failed and successful payments with JSONB gateway responses, shipments, and a tracking event per step. Returns and refunds are linked with a **data-modifying CTE**.
6. **[05_reviews_engagement.sql](seed/05_reviews_engagement.sql)**: reviews whose text matches their rating, votes, seller ratings, monthly payouts, notifications, carts, wishlists, monthly partitions created with dynamic SQL, and ~170k funnel events.

Tricks used throughout:
- `random()` in a `SELECT` list is evaluated **once per row**. But an *uncorrelated* subquery that calls `random()` runs only **once** for the whole statement. The seed adds a fake reference to the outer row (`AND n.g > 0`) to force it to re-run per row.
- `(ARRAY['a','b','c'])[1 + floor(random()*3)::int]` picks a random element.
- `power(random(), k)` with k > 1 skews picks toward small numbers, which gives realistic "popular" items.
- Everything is relative to `now()`, so the data always looks recent.

### COPY (Q02.15–Q02.18)
| Command | Where the file lives | Privilege |
|---|---|---|
| `COPY t FROM '/path/file.csv' WITH (FORMAT csv, HEADER)` | on the **database server** | superuser or `pg_read_server_files` |
| `COPY t TO STDOUT` / `COPY (query) TO '/path'` | client stream / server file | `pg_write_server_files` for files |
| `\copy t FROM 'file.csv' WITH (FORMAT csv)` | on **your machine** (psql reads it) | normal table privileges |

`COPY` is the fastest way to load data: think millions of rows per minute. Options include `FORMAT csv|text|binary`, `HEADER`, `DELIMITER`, `NULL 'x'`, `QUOTE`, `FORCE_NULL`, and (PG17) `ON_ERROR ignore`.

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `INSERT INTO … VALUES` | add rows | Q02.01, Q02.04 |
| `DEFAULT` (value) | use the column default | Q02.02 |
| `DEFAULT VALUES` | a row made only of defaults | Q02.03 |
| `RETURNING` | return values from inserted rows | Q02.05, Q02.08 |
| `INSERT INTO … SELECT` | insert the result of a query | Q02.06, Q02.14 |
| `OVERRIDING SYSTEM VALUE` | write into an `ALWAYS` identity column | Q02.07 |
| `BEGIN` / `ROLLBACK` | try a change, then undo it | Q02.08 |
| `VALUES … AS t(cols)` | inline table | Q02.09 |
| `generate_series()` | number, date or time series | Q02.10, Q02.11, Q02.14 |
| `setseed()`, `random()` | reproducible pseudo-random numbers | Q02.12 |
| `random_normal()`, `random(min,max)` | normal distribution (PG16), integer range (PG17) | Q02.13 |
| `md5()`, `gen_random_uuid()` | hashes, UUIDs | Q02.14 |
| `COPY … FROM` (csv, HEADER) | bulk import of a server file | Q02.15 |
| `COPY … TO STDOUT` | bulk export to the client | Q02.16 |
| `COPY (query) TO` | export a query result | Q02.17 |
| `\copy` (incl. `FROM PROGRAM`) | client-side bulk import/export | Q02.18 |

## Gotchas
- An explicit `NULL` is **not** the same as `DEFAULT`. `INSERT … VALUES (NULL)` stores NULL even if the column has a default.
- `INSERT` without a column list depends on column order, so it breaks when the table changes.
- Server-side `COPY` paths are on the **server**. With Docker that means inside the container, not on your laptop. Use `\copy` for local files.
- `COPY` is all-or-nothing: one bad row aborts the whole load (unless you use PG17's `ON_ERROR ignore`).
- After a bulk load, run `ANALYZE` so the planner knows the new data sizes (seed.sql does this).
- An uncorrelated subquery with `random()` gives the **same** value for every row, as explained above.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/02_seed_data/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
