# Chapter 06 · Joins

[← Previous](../05_aggregation/README.md) · [Index](../../README.md) · [Next →](../07_subqueries_set_ops/README.md)

## What you'll learn
- How joins combine rows from several tables, and how each join type behaves
- `USING`, `NATURAL`, composite keys, and why the old comma syntax is risky
- Outer joins, and the **ON-vs-WHERE trap**
- Self joins (trees, referrals, "bought together"), cross joins and non-equi joins (ranges, bands)
- `LATERAL` for top-N per group, and joining to `generate_series` to fill gaps

## Concepts

### Join types at a glance
| Join | Returns |
|---|---|
| `[INNER] JOIN … ON` | only pairs that match |
| `LEFT [OUTER] JOIN` | all left rows; right side NULL when there's no match |
| `RIGHT [OUTER] JOIN` | all right rows (rewrite it as a LEFT join for readability) |
| `FULL [OUTER] JOIN` | all rows from both sides |
| `CROSS JOIN` | every combination (rows × rows) |
| `JOIN LATERAL (subquery)` | the subquery runs once per left row and may reference it |

```
products            sellers             INNER: products that have a seller
┌────┬────────┐     ┌────┬───────┐      LEFT (sellers→products): all 200 sellers, NULL product for 10 of them
│ id │ seller │ ──► │ id │ store │      anti-join: LEFT JOIN … WHERE p.id IS NULL → those 10 sellers
└────┴────────┘     └────┴───────┘
```

### Join syntax (Q06.01–Q06.06)
- Prefer explicit `JOIN … ON`. The implicit `FROM a, b WHERE …` (Q06.02) quietly becomes a cross join if you forget the condition.
- `USING (col)` is shorthand when both tables use the same column name, and the column appears only once in the output.
- `NATURAL JOIN` joins on **every** column with the same name. It's fragile: in Q06.04 it matches `status`, `updated_at`, `sku` and `is_active` by accident.
- Composite keys join on several columns: `ON a.x = b.x AND a.y = b.y` (Q06.06).

### Outer joins and the ON-vs-WHERE trap (Q06.07–Q06.11)
In a `LEFT JOIN`, a condition on the **right** table belongs in `ON`. If you put it in `WHERE`, it discards the NULL-extended rows, and the outer join quietly becomes an inner join (Q06.09: 173 vs 200 sellers).
An **anti-join** (`LEFT JOIN … WHERE right.pk IS NULL`) finds rows that have no partner (Q06.08). `FULL JOIN` with `COALESCE` is the classic reconciliation pattern (Q06.11).

### Self joins (Q06.12–Q06.14)
Join a table to itself with two aliases: child → parent → grandparent, referrer → referee, or item A ↔ item B in the same order.
`a.id < b.id` avoids mirror duplicates (A,B)/(B,A) and self-pairs.

### Cross and non-equi joins (Q06.15–Q06.18)
A `CROSS JOIN` builds matrices. Join conditions don't have to be `=`: you can use ranges (`>= AND <`), containment (`range @> value`), or inequality for "as-of" lookups.

### LATERAL (Q06.19–Q06.21)
A subquery in `FROM` normally can't see other `FROM` items. With `LATERAL` it can, which is what makes "**top N per group**" easy.
`LEFT JOIN LATERAL … ON true` keeps left rows even when the subquery is empty. Set-returning functions such as `unnest()` are implicitly lateral.

### Joining to generated and inline rows (Q06.22–Q06.24)
- `generate_series` + `LEFT JOIN` + `COALESCE(…, 0)` gives a time series **with no missing days**.
- `JOIN (VALUES …)` applies a small rate card without creating a table.
- **Pre-aggregate before joining.** Joining two one-to-many relations (sales *and* reviews) multiplies rows and inflates totals (Q06.24).

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `INNER JOIN … ON` | matching rows only | Q06.01 |
| `FROM a, b WHERE` | implicit (old-style) join | Q06.02 |
| `USING (col)` | join on a same-named column | Q06.03 |
| `NATURAL JOIN` | join on all same-named columns (avoid) | Q06.04 |
| multi-table joins | follow foreign keys across tables | Q06.05 |
| composite-key join | `ON a.x = b.x AND a.y = b.y` | Q06.06 |
| `LEFT [OUTER] JOIN` | keep all left rows | Q06.07 |
| anti-join (`IS NULL`) | rows with no match | Q06.08 |
| ON vs WHERE in outer joins | where to put optional-side filters | Q06.09 |
| `RIGHT JOIN` | keep all right rows | Q06.10 |
| `FULL OUTER JOIN` | keep all rows from both sides | Q06.11 |
| self join | a table joined to itself | Q06.12–Q06.14 |
| `CROSS JOIN` | Cartesian product | Q06.15 |
| non-equi join | ranges and bands | Q06.16 |
| `@>` range join | value contained in a range | Q06.17 |
| as-of join | latest earlier row | Q06.18 |
| `JOIN LATERAL … ON true` | correlated subquery in FROM | Q06.19 |
| `LEFT JOIN LATERAL` | lateral that keeps empty results | Q06.20 |
| `CROSS JOIN LATERAL unnest()` | explode arrays | Q06.21 |
| `generate_series` + `LEFT JOIN` | fill gaps in a series | Q06.22 |
| `JOIN (VALUES …)` | inline lookup table | Q06.23 |
| pre-aggregated subquery join | avoid fan-out double counting | Q06.24 |

## Gotchas
- A `WHERE` filter on the nullable side of a `LEFT JOIN` turns it into an inner join.
- `count(*)` after a `LEFT JOIN` counts the NULL row as 1. Use `count(right.pk)`.
- Joining two one-to-many tables multiplies rows (fan-out). Aggregate first.
- `NATURAL JOIN` breaks silently when someone adds a column with a common name such as `updated_at`.
- Forgetting a join condition produces a Cartesian product: 30,000 × 5,000 = 150 million rows.
- `JOIN` with no qualifier means `INNER JOIN`.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/06_joins/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
