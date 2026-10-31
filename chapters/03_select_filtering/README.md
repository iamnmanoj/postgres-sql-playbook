# Chapter 03 · SELECT & Filtering: Rows, Conditions & Patterns

[← Previous](../02_seed_data/README.md) · [Index](../../README.md) · [Next →](../04_builtin_functions/README.md)

## What you'll learn
- Filter data with precision: comparisons, `AND`/`OR`/`NOT`, `IN`, `BETWEEN`, `LIKE`/`ILIKE`, `SIMILAR TO` and POSIX regex
- Handle `NULL` correctly: three-valued logic, `IS NULL`, `IS DISTINCT FROM`, `COALESCE`, `NULLIF`
- Conditional logic with `CASE`, `GREATEST` and `LEAST`
- Sort, page (`LIMIT`/`OFFSET`, `FETCH … WITH TIES`) and de-duplicate (`DISTINCT`, `DISTINCT ON`) results effectively

## Concepts

### Logical order of a SELECT
You **write** `SELECT … FROM … WHERE … GROUP BY … HAVING … ORDER BY … LIMIT`, but PostgreSQL **evaluates** it in this order:

```
FROM / JOIN  →  WHERE  →  GROUP BY  →  HAVING  →  SELECT (expressions, aliases)  →  DISTINCT  →  ORDER BY  →  LIMIT/OFFSET
```
That's why a column alias from `SELECT` can be used in `ORDER BY` (Q03.25) but **not** in `WHERE`.

### Columns and expressions (Q03.01–Q03.04)
`SELECT *` is fine for exploring, but name the columns in real code. `AS` renames a column, and an alias in double quotes keeps spaces and case.
`||` concatenates strings, and if either side is NULL the result is NULL (Q03.03). A `SELECT` doesn't even need a table (Q03.04).

### WHERE and boolean logic (Q03.05–Q03.10)
`AND` binds tighter than `OR`, so **always use parentheses** when you mix them (Q03.06).
`IN (list)` is shorthand for several `OR =` tests. `BETWEEN a AND b` includes both ends. For timestamps, prefer the half-open form `>= start AND < end` (Q03.10).

### Pattern matching (Q03.11–Q03.15)
| Operator | Meaning | Example |
|---|---|---|
| `LIKE` | `%` = any string, `_` = one character | `name LIKE 'Voltix%'` |
| `ILIKE` | case-insensitive `LIKE` (PostgreSQL extension) | `description ILIKE '%usb%'` |
| `ESCAPE` | search for a literal `%` or `_` | `LIKE '%!%%' ESCAPE '!'` |
| `SIMILAR TO` | SQL-standard pattern with `\|`, `()`, `{n}` | `sku SIMILAR TO '%-V(1\|2)'` |
| `~`, `~*`, `!~`, `!~*` | POSIX regex: match, case-insensitive match, no match | `email ~* '@outlook\.com$'` |

### NULL: "unknown" (Q03.08, Q03.16–Q03.19)
Any comparison with NULL gives NULL, not true or false, and `WHERE` keeps only rows where the condition is **true**.
- `col = NULL` is never true. Use `IS NULL` (Q03.16).
- `x NOT IN (…, NULL)` is never true. This is the most famous SQL trap (Q03.08).
- `IS [NOT] DISTINCT FROM` compares while treating NULL as an ordinary value (Q03.17).
- `COALESCE(a, b, c)` returns the first non-NULL value. `NULLIF(a, b)` returns NULL when a = b, which is the classic guard against division by zero.

### CASE, GREATEST, LEAST (Q03.20–Q03.22)
A **searched** `CASE WHEN cond THEN …` tests conditions in order, and the first true one wins. A **simple** `CASE expr WHEN value THEN …` matches a value.
`GREATEST()` and `LEAST()` pick the largest or smallest of several values *in the same row* (`max()` and `min()` work across rows, see ch05).

### ORDER BY (Q03.23–Q03.26)
You can sort by several keys, each with its own `ASC`/`DESC` and `NULLS FIRST`/`NULLS LAST`. You can also sort by an expression, an alias or a column number.
**ENUMs** sort in the order they were declared, so `status >= 'shipped'` works (Q03.26). Without `ORDER BY`, row order is **not guaranteed**.

### Paging (Q03.27–Q03.29)
- `LIMIT n OFFSET m` is simple, but it gets slower the deeper you page.
- `FETCH FIRST n ROWS ONLY` is the SQL standard. `WITH TIES` also returns rows tied with the last one.
- **Keyset pagination**, `WHERE (sort_col, id) < (last_sort_col, last_id)`, is fast at any depth and stable while rows are being inserted.

### DISTINCT and DISTINCT ON (Q03.30–Q03.31)
`DISTINCT` removes duplicate rows. `DISTINCT ON (cols)` is a PostgreSQL feature that keeps the **first row of each group**, as decided by `ORDER BY`.
It's the easiest way to get "latest X per Y".

### Type-aware comparisons (Q03.32–Q03.33)
`citext` compares case-insensitively, but only when both sides are `citext`. A plain untyped literal becomes `citext`, while a `text` value does not.
Boolean columns can be used directly in `WHERE`. `IS TRUE`, `IS NOT FALSE` and similar forms also handle NULL.

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `SELECT *`, `FROM`, `LIMIT` | read rows | Q03.01 |
| `AS` (column / table alias) | rename in the output / shorten a table name | Q03.02, Q03.03 |
| `\|\|` | concatenate strings | Q03.03 |
| `current_user`, `version()` | session info | Q03.04 |
| `WHERE`, `=`, `<>`, `<`, `>`, `<=`, `>=` | filter rows | Q03.05 |
| `AND`, `OR`, `NOT` | combine conditions | Q03.06 |
| `IN`, `NOT IN` | list membership | Q03.07, Q03.08 |
| `BETWEEN`, `NOT BETWEEN` | inclusive range | Q03.09 |
| `now()`, `interval` | relative time windows | Q03.10 |
| `LIKE`, `%`, `_` | wildcard match | Q03.11 |
| `ILIKE` | case-insensitive `LIKE` | Q03.12 |
| `ESCAPE` | literal wildcard characters | Q03.13 |
| `SIMILAR TO` | SQL-standard pattern | Q03.14 |
| `~`, `~*`, `!~` | regex match | Q03.15 |
| `IS NULL`, `IS NOT NULL` | NULL tests | Q03.16 |
| `IS DISTINCT FROM`, `IS NOT DISTINCT FROM` | NULL-safe comparison | Q03.17 |
| `COALESCE()` | first non-NULL value | Q03.18 |
| `NULLIF()` | NULL when two values are equal | Q03.19 |
| `CASE WHEN … THEN … ELSE … END` | conditional expression | Q03.20, Q03.21 |
| `GREATEST()`, `LEAST()` | row-wise max/min | Q03.22 |
| `ORDER BY … ASC/DESC` | sort | Q03.23 |
| `NULLS FIRST`, `NULLS LAST` | where NULLs sort | Q03.24 |
| `ORDER BY` alias / position | sort shortcuts | Q03.25 |
| enum ordering | sort by declaration order | Q03.26 |
| `OFFSET` | skip rows | Q03.27 |
| `FETCH FIRST/NEXT … ROWS ONLY`, `WITH TIES` | standard limiting | Q03.28 |
| row constructor comparison `(a,b) < (x,y)` | keyset pagination | Q03.29 |
| `DISTINCT` | remove duplicates | Q03.30 |
| `DISTINCT ON` | first row per group | Q03.31 |
| `citext` comparison | case-insensitive equality | Q03.32 |
| `IS TRUE`, `IS NOT FALSE` | boolean tests that handle NULL | Q03.33 |

## Gotchas
- `WHERE col = NULL` silently matches nothing.
- `NOT IN` with a list or subquery that contains NULL returns no rows. Prefer `NOT EXISTS` (ch07).
- `'a' || NULL` is NULL. Use `concat()` or `COALESCE` (ch04).
- `BETWEEN '2025-01-01' AND '2025-01-31'` on a **timestamp** misses everything after midnight on the 31st.
- `LIKE '%term%'` can't use a normal B-tree index. Use trigram indexes (ch13/14) or full-text search.
- Without `ORDER BY`, `LIMIT` returns *some* rows, not the "first" ones.
- `DISTINCT ON` needs `ORDER BY` to start with the same columns.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/03_select_filtering/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
