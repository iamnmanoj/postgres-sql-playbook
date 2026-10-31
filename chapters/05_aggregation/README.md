# Chapter 05 · Aggregation & grouping

[← Previous](../04_builtin_functions/README.md) · [Index](../../README.md) · [Next →](../06_joins/README.md)

## What you'll learn
- Summarising many rows into one with aggregate functions
- `GROUP BY` and `HAVING`, and how they differ from `WHERE`
- Conditional aggregation with `FILTER` and `CASE` (pivots)
- Aggregates that build strings, arrays and JSON
- Statistics: standard deviation, correlation, regression, median, percentiles, mode
- Multi-level reports with `GROUPING SETS`, `ROLLUP`, `CUBE` and `GROUPING()`

## Concepts

### Aggregate functions (Q05.01–Q05.03)
An aggregate turns a set of rows into one value. `count(*)` counts rows, `count(col)` counts **non-NULL** values, and `count(DISTINCT col)` counts unique ones.
`sum`, `avg`, `min` and `max` **ignore NULLs**. Over **zero rows**, `count` returns 0 and the others return **NULL**, so wrap them in `COALESCE` (Q05.03).

### GROUP BY (Q05.04–Q05.08)
`GROUP BY` splits rows into groups and runs the aggregates once per group. Every non-aggregated column in `SELECT` must be grouped.
The **exception**: if you group by a table's primary key, you may select any other column of that table (Q05.08).
You can group by expressions such as `date_trunc('month', placed_at)`, or by output position (`GROUP BY 1`).

### WHERE vs HAVING (Q05.07)
`WHERE` filters **rows before** grouping and can't use aggregates. `HAVING` filters **groups after** aggregation.

### Conditional aggregation (Q05.09–Q05.11)
`agg(...) FILTER (WHERE cond)` aggregates only the matching rows, so one table scan can produce many metrics.
`sum(CASE WHEN … THEN x ELSE 0 END)` is the portable form and is the classic way to **pivot** rows into columns.
`avg(cond::int)` gives the fraction of rows where `cond` is true.

### Building strings, arrays and JSON (Q05.12–Q05.14)
`string_agg(x, sep ORDER BY …)`, `array_agg(x ORDER BY …)`, `json_agg`/`jsonb_agg`, and `jsonb_object_agg(key, value)`.
Inside any aggregate you can add `DISTINCT` and an `ORDER BY`.

### Boolean and statistical aggregates (Q05.15–Q05.17)
`bool_and` (SQL-standard `every`) and `bool_or` answer "do all / any rows satisfy this?".
`stddev`/`stddev_samp`, `stddev_pop`, `variance`, `corr`, and `regr_slope`, `regr_intercept`, `regr_r2` give simple linear regression.

### Ordered-set aggregates (Q05.18–Q05.20)
These need the input sorted, so they use `WITHIN GROUP (ORDER BY …)`:
- `percentile_cont(f)` interpolates (the median of 1, 2 is 1.5), while `percentile_disc(f)` returns an actual value. Pass an array to get several percentiles at once.
- `mode()` returns the most frequent value.
- **Hypothetical-set** aggregates such as `rank(x)` and `percent_rank(x) WITHIN GROUP (ORDER BY col)` tell you where a value *would* rank.

### Multi-level summaries (Q05.21–Q05.24)
| Clause | Produces groups for |
|---|---|
| `GROUPING SETS ((a), (b), ())` | exactly the listed sets |
| `ROLLUP (a, b)` | (a, b), (a), () — hierarchical subtotals |
| `CUBE (a, b)` | (a, b), (a), (b), () — every combination |
| `GROUP BY DISTINCT …` | removes duplicate sets (PG14) |

In subtotal rows the "rolled-up" columns are NULL. `GROUPING(col)` returns 1 when a NULL means "subtotal" rather than real data.

### Extras (Q05.25–Q05.28)
`any_value(col)` (PG16) returns an arbitrary value from the group. Aggregates can't be nested directly (`avg(count(*))`), so aggregate twice with a derived table (Q05.26–Q05.27). A weighted average is `sum(x*w)/sum(w)` (Q05.28).

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `count(*)`, `count(col)`, `count(DISTINCT col)` | count rows / values / unique values | Q05.01 |
| `sum()`, `avg()`, `min()`, `max()` | basic aggregates | Q05.02 |
| `COALESCE(sum(…), 0)` | handle empty groups | Q05.03 |
| `GROUP BY` | one result row per group | Q05.04–Q05.06 |
| `HAVING` | filter groups | Q05.07 |
| functional dependency | select columns that depend on the grouped PK | Q05.08 |
| `FILTER (WHERE …)` | conditional aggregate | Q05.09, Q05.11 |
| `sum(CASE …)` | pivot | Q05.10 |
| `string_agg()` | concatenate a group | Q05.12 |
| `array_agg()` | collect into an array | Q05.13 |
| `json_agg()`, `jsonb_agg()`, `jsonb_object_agg()` | build JSON | Q05.14 |
| `bool_and()`, `bool_or()`, `every()` | boolean aggregates | Q05.15 |
| `stddev()`, `stddev_pop()`, `variance()` | spread | Q05.16 |
| `corr()`, `regr_slope()`, `regr_intercept()`, `regr_r2()` | correlation and regression | Q05.17 |
| `percentile_cont()`, `percentile_disc()`, `WITHIN GROUP` | percentiles and median | Q05.18 |
| `mode()` | most frequent value | Q05.19 |
| `rank() / percent_rank() WITHIN GROUP` | hypothetical rank | Q05.20 |
| `GROUPING SETS` | several groupings at once | Q05.21 |
| `ROLLUP`, `GROUPING()` | hierarchical subtotals | Q05.22 |
| `CUBE` | all subtotal combinations | Q05.23 |
| `GROUP BY DISTINCT` | dedupe grouping sets | Q05.24 |
| `any_value()` | arbitrary value from the group | Q05.25 |
| nested aggregation via derived table | aggregate of aggregates | Q05.26, Q05.27 |
| weighted average | `sum(x*w)/sum(w)` | Q05.28 |

## Gotchas
- `count(col)` skips NULLs, and `count(*)` doesn't. Pick deliberately.
- `avg` of an integer column returns `numeric`, but `sum(int)/count(*)` is integer division.
- `sum()` over no rows is **NULL**, not 0.
- You can't use a column alias from `SELECT` in `WHERE` or `HAVING` (in PostgreSQL you *can* use it in `GROUP BY` and `ORDER BY`).
- Joining before aggregating can multiply rows: an order with 3 items is counted 3 times. Use `count(DISTINCT o.order_id)`, or aggregate first and then join.
- `string_agg` and `array_agg` order is random unless you add `ORDER BY` inside the call.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/05_aggregation/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
