# Chapter 08 · CTEs (WITH) & recursive queries

[← Previous](../07_subqueries_set_ops/README.md) · [Index](../../README.md) · [Next →](../09_window_functions/README.md)

## What you'll learn
- Making complex queries readable with **Common Table Expressions**
- Chaining and reusing CTEs, and controlling materialisation
- `WITH RECURSIVE` for trees (categories), chains (referrals), graphs (routes) and generated series
- `SEARCH` and `CYCLE` clauses (PG14)
- **Data-modifying CTEs**: archive, multi-table inserts, and update-and-report in a single statement

## Concepts

### What a CTE is (Q08.01–Q08.05)
```sql
WITH step1 AS (…), step2 AS (SELECT … FROM step1)
SELECT … FROM step2;
```
A CTE is a named, temporary result that exists for **one statement**. CTEs turn nested subqueries into a top-down pipeline you can read step by step.
Each CTE can use any CTE defined before it, and you can reference a CTE several times (Q08.03).

**Materialisation (Q08.04).** Since PG12, a non-recursive, side-effect-free CTE that's referenced **once** is *inlined* into the main query, so filters can be pushed into it.
`AS MATERIALIZED` forces it to be computed once and stored, which acts as an optimisation fence. `AS NOT MATERIALIZED` forces inlining even when the CTE is referenced several times.
Compare the two `EXPLAIN` outputs: the inlined version can use both the `user_id` and `placed_at` indexes.

### Recursive CTEs (Q08.06–Q08.15)
```sql
WITH RECURSIVE r AS (
    <anchor query>            -- runs once and seeds the result
    UNION ALL
    <recursive query>         -- references r; runs repeatedly on the rows from the previous step
)
SELECT … FROM r;
```
Iteration stops when the recursive part returns **no new rows**, so always include a stop condition (a depth limit, `WHERE n < 10`, or the natural end of a tree).

| Pattern | Example |
|---|---|
| walk **down** a tree (descendants) | Q08.07: subcategories of Electronics |
| walk **up** a tree (ancestors) | Q08.08: breadcrumbs |
| materialise **paths** (arrays) and roll values up | Q08.09: subtree revenue |
| follow a **chain** | Q08.10: referral chain |
| carry the **root** through the recursion | Q08.11: downline size per referrer |
| **order** the output | Q08.12: `SEARCH DEPTH FIRST` / `BREADTH FIRST BY col SET ordcol` |
| detect **cycles** | Q08.13: `CYCLE col SET is_cycle USING path` |
| generate **series** / carry **state** | Q08.14, Q08.15 |

`UNION` instead of `UNION ALL` in a recursive CTE drops duplicate rows, which also stops some simple cycles.

### Data-modifying CTEs (Q08.16–Q08.19)
`INSERT`, `UPDATE` and `DELETE` with `RETURNING` can live inside `WITH`. Their returned rows feed later CTEs or the main query, which allows:
- **Moving** rows atomically: `DELETE … RETURNING` → `INSERT` (Q08.16)
- **Creating related rows** in one round trip: user → address → cart (Q08.17)
- **Updating and reporting** at the same time (Q08.18)

All parts of the statement see the **same snapshot**. They can't see each other's changes except through `RETURNING` (Q08.19).
Every data-modifying CTE runs to completion, even if the main query never reads it.

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `WITH name AS (…)` | define a CTE | Q08.01 |
| chained CTEs | pipeline of named steps | Q08.02, Q08.05 |
| CTE reuse | reference a CTE several times | Q08.03 |
| `MATERIALIZED`, `NOT MATERIALIZED` | control inlining | Q08.04 |
| `WITH RECURSIVE` (anchor + `UNION ALL` + recursive member) | iterative queries | Q08.06 |
| tree traversal (down) with depth | descendants | Q08.07 |
| tree traversal (up) | ancestors and breadcrumbs | Q08.08 |
| array path + `@>` | subtree membership | Q08.09 |
| chain following | referral chain | Q08.10 |
| carrying a root id | group by tree root | Q08.11 |
| `SEARCH DEPTH FIRST BY … SET` / `SEARCH BREADTH FIRST BY` | traversal order | Q08.12 |
| `CYCLE … SET … USING` | cycle detection | Q08.13 |
| recursive date series | alternative to generate_series | Q08.14 |
| state accumulation | running calculation across steps | Q08.15 |
| `DELETE … RETURNING` in CTE | move or archive rows | Q08.16 |
| `INSERT … RETURNING` in CTE | multi-table insert | Q08.17 |
| `UPDATE … RETURNING` in CTE | update and report | Q08.18 |
| snapshot visibility | CTEs don't see each other's writes | Q08.19 |

## Gotchas
- A recursive CTE without a stop condition on cyclic data runs **forever**. Add a depth limit or `CYCLE`.
- The recursive member can reference the CTE only **once**, and can't use aggregates, `LIMIT` or `ORDER BY` on it directly.
- Column types must match between the anchor and the recursive part. Cast in the anchor if needed (for example `name::text`).
- Before PG12, CTEs were *always* materialised. Old advice that "CTEs are slow" refers to that.
- In a data-modifying CTE, a later `SELECT` from the base table won't see the new rows. Use `RETURNING`.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/08_ctes_recursive/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
