# Chapter 10 · Changing Data: UPDATE, DELETE, UPSERT & MERGE

[← Previous](../09_window_functions/README.md) · [Index](../../README.md) · [Next →](../11_transactions_locking/README.md)

## What you'll learn
- `UPDATE`: simple, computed, join-based (`FROM`), multi-column, conditional, JSONB and arrays
- `DELETE`: simple, join-based (`USING`), anti-join, batched
- `RETURNING` to see exactly what changed
- **Upserts** with `INSERT … ON CONFLICT`
- **`MERGE`** (PG15), with `RETURNING merge_action()` and `WHEN NOT MATCHED BY SOURCE` (PG17)
- `TRUNCATE`

> Every demo that touches ShopSphere tables runs inside `BEGIN; … ROLLBACK;`, so the data stays intact. Transactions are explained in [chapter 11](../11_transactions_locking/README.md).

## Concepts

### UPDATE (Q10.01–Q10.07)
```sql
UPDATE table [AS t] SET col = expr [, …] [FROM other …] WHERE … [RETURNING …];
```
- With no `WHERE`, **every row** is updated. Always write the `WHERE` first.
- `UPDATE … FROM` joins to another table or subquery (Q10.03). If a target row matches several source rows, one of them is used arbitrarily, so make the source unique.
- `SET (a, b) = (SELECT x, y …)` updates several columns from one subquery (Q10.04).
- `IS DISTINCT FROM` in the `WHERE` skips rows that wouldn't change. That avoids pointless writes, dead tuples and trigger firings (Q10.03).
- Generated columns can't be assigned (Q10.07). They update themselves when their inputs change (Q10.04).

### DELETE (Q10.08–Q10.11)
`DELETE FROM t USING other WHERE …` is the join form (Q10.09). `NOT EXISTS` deletes orphans (Q10.10).
On big tables, **delete in batches** to keep locks and WAL bursts small (Q10.11). For time-series data, dropping partitions is far cheaper (ch18).

### RETURNING
`INSERT`, `UPDATE`, `DELETE` and `MERGE` can all return the affected rows. Wrap the statement in a CTE to aggregate or limit those rows (Q10.02, Q10.08).
The trick `(xmax = 0) AS inserted` in an upsert's `RETURNING` tells you whether each row was inserted or updated (Q10.13).

### UPSERT: `INSERT … ON CONFLICT` (Q10.12–Q10.16)
```sql
INSERT INTO t AS x (…) VALUES (…)
ON CONFLICT (unique_cols) [WHERE partial_index_predicate]  |  ON CONFLICT ON CONSTRAINT name
DO NOTHING
DO UPDATE SET col = EXCLUDED.col [WHERE condition];
```
- The conflict target must match a **unique index or constraint**, including partial ones (Q10.16).
- `EXCLUDED` refers to the row you tried to insert, and the target alias (`x`) refers to the existing row.
- It's **atomic and concurrency-safe**. There's no race between "check" and "insert", unlike `SELECT` then `INSERT`.
- A single statement can't affect the same row twice ("ON CONFLICT DO UPDATE command cannot affect row a second time"), so de-duplicate the input first.

### MERGE (Q10.17–Q10.19)
```sql
MERGE INTO target t USING source s ON t.key = s.key
WHEN MATCHED [AND cond] THEN UPDATE SET … | DELETE | DO NOTHING
WHEN NOT MATCHED [BY TARGET] [AND cond] THEN INSERT (…) VALUES (…) | DO NOTHING
WHEN NOT MATCHED BY SOURCE [AND cond] THEN UPDATE … | DELETE | DO NOTHING   -- PG17
[RETURNING merge_action(), …]                                                -- PG17
```
`WHEN` clauses are checked in order, and the first matching one wins.
**MERGE vs ON CONFLICT**: `MERGE` is more expressive (it can delete, and it can handle rows missing from the source), but it isn't protected against concurrent inserts the way `ON CONFLICT` is.
For high-concurrency "insert or update", prefer `ON CONFLICT`.

### TRUNCATE (Q10.20)
`TRUNCATE` empties tables instantly by swapping in new files instead of deleting row by row. `RESTART IDENTITY` resets identity columns, and `CASCADE` also truncates tables that reference this one.
It's transactional in PostgreSQL, but it takes an `ACCESS EXCLUSIVE` lock and doesn't fire `DELETE` triggers.

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `UPDATE … SET … WHERE` | modify rows | Q10.01 |
| `RETURNING` | return affected rows | Q10.02, Q10.04, Q10.13 |
| `UPDATE … FROM` | update via a join | Q10.03 |
| `SET (a, b) = (SELECT …)` | multi-column update | Q10.04 |
| `SET col = CASE …` | conditional update | Q10.05 |
| `jsonb_set()` / `array_append()` in UPDATE | modify document and array columns | Q10.06 |
| generated column write error | can only be updated to DEFAULT | Q10.07 |
| `DELETE FROM … RETURNING` | remove rows | Q10.08 |
| `DELETE … USING` | delete via a join | Q10.09 |
| `DELETE … WHERE NOT EXISTS` | delete orphans | Q10.10 |
| batched delete, `ctid` | delete in chunks | Q10.11 |
| `ON CONFLICT DO NOTHING` | skip duplicates | Q10.12 |
| `ON CONFLICT (…) DO UPDATE`, `EXCLUDED` | upsert | Q10.13, Q10.14 |
| `xmax = 0` | inserted vs updated in an upsert | Q10.13 |
| `ON CONFLICT ON CONSTRAINT`, `DO UPDATE … WHERE` | named target, conditional update | Q10.15 |
| `ON CONFLICT (…) WHERE …` | partial unique index target | Q10.16 |
| `MERGE … WHEN MATCHED / NOT MATCHED` | sync from a source | Q10.17 |
| `MERGE … RETURNING merge_action()` | report actions (PG17) | Q10.18 |
| `WHEN NOT MATCHED BY SOURCE`, `DO NOTHING` | full sync (PG17) | Q10.19 |
| `TRUNCATE … RESTART IDENTITY CASCADE` | empty tables fast | Q10.20 |

## Gotchas
- **Run a `SELECT` with the same `WHERE` first**, or do the change inside `BEGIN` and check before you `COMMIT`.
- `UPDATE … FROM` with duplicate join matches updates each row once, with an unpredictable source row.
- An upsert needs a unique index on exactly the conflict columns, otherwise you get "there is no unique or exclusion constraint matching the ON CONFLICT specification".
- Updating a row creates a new row version (MVCC). Mass updates bloat tables until `VACUUM` runs (ch14).
- `DELETE` doesn't return disk space to the OS immediately. `TRUNCATE` and `DROP PARTITION` do.
- `TRUNCATE … CASCADE` can wipe tables you didn't name. Read the NOTICE.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/10_dml_upsert_merge/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
