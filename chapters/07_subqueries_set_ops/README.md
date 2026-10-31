# Chapter 07 · Subqueries & set operations

[← Previous](../06_joins/README.md) · [Index](../../README.md) · [Next →](../08_ctes_recursive/README.md)

## What you'll learn
- Scalar, row, table (derived) and correlated subqueries, and where each can appear
- `IN`, `EXISTS`, `NOT EXISTS`, `ANY`/`SOME`/`ALL`
- Why `NOT IN` with NULLs returns nothing, and why `NOT EXISTS` is the safe anti-join
- "For all" questions (relational division) with a double `NOT EXISTS`
- Combining result sets with `UNION [ALL]`, `INTERSECT [ALL]` and `EXCEPT [ALL]`

## Concepts

### Kinds of subquery
| Kind | Returns | Typical place | Query |
|---|---|---|---|
| scalar | 1 row × 1 column | `SELECT` list, `WHERE x > (…)`, `HAVING`, `ORDER BY` | Q07.01, Q07.02, Q07.15, Q07.16 |
| row | 1 row × n columns | `WHERE (a, b) = (…)` | Q07.14 |
| table / derived | many rows | `FROM (…) AS alias`, `IN (…)` | Q07.04, Q07.13 |
| correlated | depends on the outer row | anywhere: it references outer columns | Q07.06, Q07.16 |

A scalar subquery that returns 2+ rows is an error. If it returns 0 rows, the result is NULL (Q07.03).

### IN vs EXISTS vs JOIN
- `x IN (subquery)` tests membership. The planner usually turns it into a **semi-join**.
- `EXISTS (subquery)` asks "is there at least one row?". What the subquery selects doesn't matter (`SELECT 1` is the convention).
- A `JOIN` repeats the outer row once per match. `EXISTS` and `IN` never duplicate it.

### The NOT IN NULL trap (Q07.05)
`x NOT IN (1, 2, NULL)` means `x <> 1 AND x <> 2 AND x <> NULL`. The last test is NULL, so the whole condition is never true.
If a subquery's column can contain NULL, `NOT IN` returns **zero rows**. Use `NOT EXISTS` (Q07.08), which has no such problem.

### Relational division (Q07.09)
"Users who bought **every** brand in a list" becomes "users for whom there is **no** brand in the list that they have **not** bought": two nested `NOT EXISTS`.

### ANY / SOME / ALL (Q07.10–Q07.12)
`x op ANY (set)` is true if the comparison holds for at least one element (`SOME` is a synonym, and `= ANY` equals `IN`).
`x op ALL (set)` holds for every element. Over an **empty** set, `ALL` is true and `ANY` is false.
Both work with arrays, `= ANY($1::int[])`, which is the idiomatic way to pass a list as one parameter from application code.

### Set operations (Q07.17–Q07.23)
| Operator | Result |
|---|---|
| `UNION` | rows in A or B, duplicates removed |
| `UNION ALL` | A followed by B, duplicates kept (cheaper: prefer it when duplicates are impossible or wanted) |
| `INTERSECT [ALL]` | rows in both |
| `EXCEPT [ALL]` | rows in A that aren't in B |

The rules:
- Both sides need the same **number of columns** with **compatible types**. Cast when needed (Q07.22).
- Column names come from the first query.
- A final `ORDER BY` or `LIMIT` applies to the whole result. Wrap a branch in parentheses to sort or limit just that branch (Q07.23).
- `INTERSECT` binds tighter than `UNION` and `EXCEPT`.

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| scalar subquery | single value from a query | Q07.01, Q07.02 |
| cardinality violation | a scalar subquery returned >1 row | Q07.03 |
| `IN (subquery)` | membership | Q07.04 |
| `NOT IN` NULL trap | NULL makes `NOT IN` return nothing | Q07.05 |
| correlated subquery | references the outer query | Q07.06 |
| `EXISTS` | semi-join | Q07.07 |
| `NOT EXISTS` | NULL-safe anti-join | Q07.08 |
| double `NOT EXISTS` | relational division ("for all") | Q07.09 |
| `ANY`, `SOME` | at least one element matches | Q07.10, Q07.12 |
| `ALL` | every element matches | Q07.11, Q07.12 |
| derived table | subquery in `FROM` | Q07.13 |
| row subquery `(a,b) = (…)`, `(a,b) IN (…)` | multi-column comparison | Q07.14 |
| subquery in `HAVING` | compare groups to a global value | Q07.15 |
| subquery in `ORDER BY` | sort by a computed lookup | Q07.16 |
| `UNION` | combine and de-duplicate | Q07.17 |
| `UNION ALL` | combine and keep duplicates | Q07.18, Q07.22 |
| `INTERSECT` | common rows | Q07.19 |
| `EXCEPT` | difference | Q07.20 |
| `INTERSECT ALL`, `EXCEPT ALL` | multiset versions | Q07.21 |
| set-operation precedence / parentheses | per-branch `ORDER BY`/`LIMIT` | Q07.23 |

## Gotchas
- Prefer `NOT EXISTS` over `NOT IN (subquery)`.
- `UNION` sorts or hashes to remove duplicates. Use `UNION ALL` unless you really need de-duplication.
- A correlated subquery in the `SELECT` list can run once per row. On large tables, rewrite it as a join or `LATERAL` and check with `EXPLAIN` (ch14).
- `ALL (empty set)` is **true**, which can surprise you (`price > ALL(no tablets)` matches everything).
- Set operations compare whole rows, and NULLs count as equal there (unlike `=`).

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/07_subqueries_set_ops/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
