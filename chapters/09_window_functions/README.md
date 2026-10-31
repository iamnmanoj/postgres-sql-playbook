# Chapter 09 · Window functions

[← Previous](../08_ctes_recursive/README.md) · [Index](../../README.md) · [Next →](../10_dml_upsert_merge/README.md)

## What you'll learn
- Computing over "a window of related rows" **without collapsing them**, unlike `GROUP BY`
- `PARTITION BY`, window `ORDER BY` and frames (`ROWS`, `RANGE`, `GROUPS`, `EXCLUDE`)
- Ranking (`row_number`, `rank`, `dense_rank`, `percent_rank`, `cume_dist`, `ntile`)
- Offsets (`lag`, `lead`, `first_value`, `last_value`, `nth_value`)
- Analytics patterns: top-N per group, de-duplication, running totals, moving averages, YoY growth, gaps-and-islands, sessionization, cohorts, Pareto/ABC

## Concepts

### Anatomy
```sql
function(args) [FILTER (WHERE …)] OVER (
    [PARTITION BY …]          -- split rows into independent groups
    [ORDER BY …]              -- order inside each partition
    [frame_clause]            -- which rows around the current row count
)
```
With `GROUP BY`, 10 rows can become 1. With a window function, 10 rows stay 10, and each row gets a computed value (Q09.01–Q09.02).
Window functions run **after** `WHERE`, `GROUP BY` and `HAVING`, which means:
- you can't filter on them in `WHERE`. Wrap the query and filter outside (Q09.04);
- you *can* window over aggregates: `sum(sum(x)) OVER (…)` (Q09.11).

### Ranking (Q09.03–Q09.07)
| Function | Ties 100, 90, 90, 80 |
|---|---|
| `row_number()` | 1, 2, 3, 4 |
| `rank()` | 1, 2, 2, 4 |
| `dense_rank()` | 1, 2, 2, 3 |
| `percent_rank()` | (rank − 1) / (rows − 1) |
| `cume_dist()` | share of rows ≤ the current row |
| `ntile(n)` | bucket number 1…n |

**Top-N per group** = `row_number() OVER (PARTITION BY g ORDER BY metric DESC)` and then `WHERE rn <= N`. **Dedup** = keep `rn = 1`.

### Offsets (Q09.08–Q09.10)
`lag(x, n, default)` and `lead(x, n, default)` read an earlier or later row. `first_value`, `last_value` and `nth_value` read rows from the frame.

### Frames (Q09.10–Q09.15)
The **default frame** with an `ORDER BY` is `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. That's why `last_value()` returns the *current* row unless you widen the frame (Q09.10), and why `sum() OVER (ORDER BY …)` gives a running total (Q09.11).

| Frame unit | Counts… | Example |
|---|---|---|
| `ROWS` | physical rows | `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW`: last 7 rows |
| `RANGE` | values within a distance of the current ORDER BY value | `RANGE BETWEEN interval '30 days' PRECEDING AND CURRENT ROW` |
| `GROUPS` | groups of peers (equal ORDER BY values) | `GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING` |

`EXCLUDE CURRENT ROW | GROUP | TIES | NO OTHERS` removes rows from the frame (Q09.15).
The `WINDOW name AS (…)` clause names a window for reuse, and other windows can extend it (Q09.16).

### Patterns (Q09.18–Q09.22)
- **Gaps and islands**: `value − row_number()` stays constant inside a run of consecutive values (Q09.18).
- **Sessionization**: flag "new session" when the gap from `lag()` exceeds a threshold, then take a running `sum()` of the flags (Q09.19).
- **Cohorts**: `min(month) OVER (PARTITION BY user)` gives each user's first month. Pivot the months-since-first with `FILTER` (Q09.20).
- **Pareto / ABC**: a running share of revenue, `sum() OVER (ORDER BY revenue DESC) / sum() OVER ()` (Q09.21).

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `OVER ()` | window over all rows | Q09.01 |
| `PARTITION BY` | per-group windows | Q09.02 |
| `row_number()`, `rank()`, `dense_rank()` | ranking | Q09.03 |
| top-N per group | rank, then filter in an outer query | Q09.04 |
| `percent_rank()`, `cume_dist()` | relative rank | Q09.05 |
| `ntile()` | equal buckets | Q09.06 |
| dedup with `row_number()` | keep the latest row per key | Q09.07 |
| `lag()`, `lead()` | previous / next row | Q09.08, Q09.09 |
| `lag(x, n, default)` | offset with a default (YoY) | Q09.09 |
| `first_value()`, `last_value()`, `nth_value()` | values from the frame | Q09.10 |
| `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` | full-partition frame | Q09.10, Q09.15 |
| running total `sum() OVER (ORDER BY)` | cumulative sum | Q09.11 |
| `ROWS BETWEEN n PRECEDING AND CURRENT ROW` | moving window | Q09.12 |
| `RANGE BETWEEN interval … PRECEDING` | value-distance frame | Q09.13 |
| `GROUPS BETWEEN` | peer-group frame | Q09.14 |
| `EXCLUDE CURRENT ROW` | remove rows from the frame | Q09.15 |
| `WINDOW w AS (…)` | named, reusable window | Q09.03, Q09.16 |
| `FILTER` + `OVER` | conditional window aggregate | Q09.17 |
| gaps and islands | detect streaks | Q09.18 |
| sessionization | split events by inactivity | Q09.19 |
| cohort retention | first-period grouping | Q09.20 |
| ABC / Pareto | cumulative share | Q09.21 |
| durations with `lag()` | time between consecutive events | Q09.22 |

## Gotchas
- `last_value()` with the default frame returns the current row. Specify `ROWS BETWEEN … UNBOUNDED FOLLOWING`.
- `row_number()` with ties is **non-deterministic**. Add a tiebreaker column to the `ORDER BY`.
- Window functions can't go in `WHERE`, `GROUP BY` or `HAVING`. Use a subquery or CTE.
- `RANGE` with an offset needs exactly one `ORDER BY` column of a numeric, date or time type.
- A window over a big unsorted table sorts it. An index matching `PARTITION BY` + `ORDER BY` can help (ch14).

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/09_window_functions/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
