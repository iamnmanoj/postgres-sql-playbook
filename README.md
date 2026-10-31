# 🐘 PostgreSQL Playbook: learn every kind of query by building **ShopSphere**

A hands-on PostgreSQL 17 course built around one realistic, complex application: **ShopSphere**, a multi-seller
e-commerce marketplace (think Amazon/Flipkart-lite). You get a full schema, ~740k rows of realistic generated data,
and **440 unique, runnable queries** grouped into 20 concept chapters. Each chapter has an explanation,
a keyword table, gotchas, exercises and solutions.

> Every query answers a real business question ("top 3 products per seller", "which coupons were valid when this order
> was placed", "isolate each seller's data with row-level security"…), and no two queries teach the same thing.

## Quick start
```bash
# needs Docker + Docker Compose v2
scripts/reset.sh                     # start postgres:17 in Docker, build schema, load seed data (~15 s)
scripts/psql.sh                      # interactive psql on the shopsphere database
scripts/psql.sh -e -f /playbook/chapters/03_select_filtering/queries.sql   # run a chapter
```
Connect from any GUI (VS Code PostgreSQL extension, DBeaver, pgAdmin…) at `localhost:5432`, user `postgres`, password `postgres`, database `shopsphere`.
See [chapter 00](chapters/00_setup/README.md) for details and a psql cheat sheet.

## Learning path

| # | Chapter | Category | You'll learn | Queries | Exercises |
|---|---|---|---|---:|---:|
| 00 | [Setup](chapters/00_setup/README.md) | Setup | Docker, psql, meta-commands | – | – |
| 01 | [DDL & the schema](chapters/01_ddl_schema/README.md) | **Foundations** | data types, constraints, identity, enums, domains, ALTER, ER diagram | 27 | 8 |
| 02 | [Seeding data](chapters/02_seed_data/README.md) | Foundations | INSERT forms, generate_series, random data, COPY / \copy | 18 | 7 |
| 03 | [SELECT & filtering](chapters/03_select_filtering/README.md) | **Querying basics** | WHERE, LIKE/regex, NULL logic, CASE, ORDER BY, paging, DISTINCT ON | 33 | 9 |
| 04 | [Built-in functions](chapters/04_builtin_functions/README.md) | Querying basics | strings, numbers, dates and time zones, casting | 28 | 9 |
| 05 | [Aggregation](chapters/05_aggregation/README.md) | **Analysis** | GROUP BY, HAVING, FILTER, percentiles, ROLLUP/CUBE/GROUPING SETS | 28 | 9 |
| 06 | [Joins](chapters/06_joins/README.md) | Analysis | inner/outer/self/cross/non-equi joins, LATERAL, gap filling | 24 | 9 |
| 07 | [Subqueries & set operations](chapters/07_subqueries_set_ops/README.md) | Analysis | EXISTS, ANY/ALL, NOT IN trap, UNION/INTERSECT/EXCEPT | 23 | 8 |
| 08 | [CTEs & recursion](chapters/08_ctes_recursive/README.md) | **Advanced querying** | WITH, MATERIALIZED, WITH RECURSIVE, SEARCH/CYCLE, data-modifying CTEs | 19 | 6 |
| 09 | [Window functions](chapters/09_window_functions/README.md) | Advanced querying | ranking, lag/lead, frames, running totals, cohorts, gaps and islands | 22 | 9 |
| 10 | [UPDATE, DELETE, UPSERT, MERGE](chapters/10_dml_upsert_merge/README.md) | **Changing data** | UPDATE…FROM, DELETE…USING, ON CONFLICT, MERGE (PG17), TRUNCATE | 20 | 7 |
| 11 | [Transactions & locking](chapters/11_transactions_locking/README.md) | Changing data | ACID, isolation levels, row locks, SKIP LOCKED, deadlocks, MVCC | 23 | 7 |
| 12 | [JSONB & arrays](chapters/12_jsonb_arrays/README.md) | **Rich data types** | operators, jsonpath, JSON_TABLE (PG17), arrays | 24 | 9 |
| 13 | [Full-text search](chapters/13_full_text_search/README.md) | Rich data types | tsvector/tsquery, ranking, highlighting, pg_trgm fuzzy search | 19 | 7 |
| 14 | [Indexes & performance](chapters/14_indexes_performance/README.md) | **Performance** | EXPLAIN, B-tree/GIN/GiST/BRIN/hash, statistics, VACUUM, tuning | 27 | 7 |
| 15 | [Views & materialized views](chapters/15_views_materialized/README.md) | **Database programming** | views, updatable views, security_invoker, matviews | 16 | 5 |
| 16 | [Functions & procedures](chapters/16_functions_procedures/README.md) | Database programming | SQL & PL/pgSQL functions, procedures, dynamic SQL, cursors | 21 | 6 |
| 17 | [Triggers](chapters/17_triggers/README.md) | Database programming | audit logs, history tables, transition tables, event triggers | 14 | 5 |
| 18 | [Partitioning](chapters/18_partitioning/README.md) | **Scale & operations** | RANGE/LIST/HASH, pruning, attach/detach, retention | 17 | 5 |
| 19 | [Security & RLS](chapters/19_security_rls/README.md) | Scale & operations | roles, GRANT/REVOKE, column privileges, row-level security | 17 | 6 |
| 20 | [Advanced extras](chapters/20_advanced_extras/README.md) | Scale & operations | ranges, LISTEN/NOTIFY, catalogs, collations, cursors, FDW, backups | 20 | 6 |
| | **Total** | | | **440** | **144** |

**Suggested pace**: work through chapters 01–07 in order, because they build on each other. After that, pick topics in any order.
For each chapter: read the README, run `queries.sql` query by query (change things!), try `exercises.sql` yourself, then compare with `solutions.sql`.

## Reference docs in this repo
| File | What it is |
|---|---|
| [GLOSSARY.md](GLOSSARY.md) | every keyword and function A–Z with meaning and chapter, plus core concepts (ACID, MVCC, sargable…) |
| [KEYWORD_INDEX.md](KEYWORD_INDEX.md) | every query by chapter and category, and a keyword → query-id lookup |
| [TIPS.md](TIPS.md) | common mistakes, performance and design tips |
| [chapters/01_ddl_schema/README.md](chapters/01_ddl_schema/README.md#the-shopsphere-data-model) | the data model and ER diagram |

## The ShopSphere data set
| Area | Tables | Rows (approx.) |
|---|---|---|
| People | users, addresses, roles, sellers, payouts, notifications | 5k users, 10k addresses, 200 sellers, 20k notifications |
| Catalog | categories (3-level tree), brands, products (JSONB attributes, tags[], tsvector), variants, images, price history, reviews, votes | 3k products, 6.4k variants, 19.5k reviews |
| Logistics | warehouses, inventory, stock movements, shipments, tracking events | 12.8k stock rows, 28k shipments, 110k events |
| Sales | carts, wishlists, coupons (tstzrange), orders, items, status history, payments, refunds, returns | 30k orders, 72k items, 31k payments |
| Analytics | click-stream events, partitioned by month | 170k events |

The data is generated relative to **now()** (it always covers the last ~2 years) and is reproducible (`setseed`). It deliberately contains edge cases to query for: NULLs, messy names, empty categories, brands without products, expired, future and inactive coupons, failed payments, lost shipments, and misspelled searches.

## Repository layout
```
docker-compose.yml          postgres:17 + pg_stat_statements, repo mounted at /playbook
scripts/
  reset.sh                  drop & rebuild a database (schema + seed)
  psql.sh                   psql inside the container (DB=name to choose a database)
  run_all.sh                rebuild, then run every chapter's queries.sql + solutions.sql (CI-style check)
  check.sh                  run given chapter files twice (idempotency check)
  build_index.py            regenerate KEYWORD_INDEX.md and GLOSSARY.md, validate query ids
chapters/NN_topic/
  README.md                 lesson: concepts, keyword table, gotchas
  queries.sql               runnable lesson queries, each with an ID, Keywords and Business question header
  exercises.sql             practice questions
  solutions.sql             runnable answers
```

## Conventions
- Each query header looks like this:
  ```sql
  -- [Q05.07] Filter GROUPS (not rows) with HAVING
  -- Keywords: HAVING
  -- Business question: Loyal customers: more than 20 delivered orders.
  ```
- Table names are always schema-qualified (`sales.orders`), so you always know where a table lives.
- Anything that modifies ShopSphere data runs inside `BEGIN … ROLLBACK`, so the data set stays stable. Demo objects live in `playground_NN` schemas.
- Every SQL file is **idempotent**: you can run it again at any time. `scripts/run_all.sh` proves that all chapters run cleanly in sequence.

## Verify everything
```bash
scripts/run_all.sh                   # ~1 minute: rebuild + run all 20 chapters and solutions
python3 scripts/build_index.py       # regenerate the index and glossary after editing queries
```

## Cleaning up
```bash
docker compose down -v               # remove the container and its data volume
```
