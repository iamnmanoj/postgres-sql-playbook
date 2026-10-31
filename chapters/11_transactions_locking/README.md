# Chapter 11 · Transactions, isolation & locking

[← Previous](../10_dml_upsert_merge/README.md) · [Index](../../README.md) · [Next →](../12_jsonb_arrays/README.md)

## What you'll learn
- **ACID**, and how `BEGIN` / `COMMIT` / `ROLLBACK` / `SAVEPOINT` work
- The three isolation levels and the anomalies each one prevents
- Row locks (`FOR UPDATE`, `FOR NO KEY UPDATE`, `FOR SHARE`, `FOR KEY SHARE`), `NOWAIT` and `SKIP LOCKED`
- Table locks, advisory locks, timeouts and deadlocks
- Watching sessions and locks: `pg_stat_activity`, `pg_locks`, `pgrowlocks`
- **MVCC**: why readers never block writers, and what `xmin`, `xmax` and `ctid` mean
- Designing a real **checkout transaction**

> [queries.sql](queries.sql) uses the `dblink` extension to open a **second connection** ("session B"), so it can show blocking, serialization failures and deadlocks without you having to type in two terminals.
> It also uses psql's `\gset` to store a returned id in a variable, so run it with `psql` rather than a GUI.

## Concepts

### ACID
| Letter | Meaning | In PostgreSQL |
|---|---|---|
| **A**tomicity | all or nothing | `ROLLBACK`; any error aborts the whole transaction (Q11.03) |
| **C**onsistency | constraints always hold | CHECK, FK and UNIQUE, checked per statement or at commit if deferred (Q11.22) |
| **I**solation | concurrent transactions don't see half-done work | isolation levels (Q11.06–Q11.09) |
| **D**urability | committed means it survives a crash | write-ahead log (WAL) |

Outside an explicit `BEGIN`, **every statement is its own transaction** (autocommit).

### Transaction control (Q11.01–Q11.05)
`BEGIN`/`START TRANSACTION` → … → `COMMIT` or `ROLLBACK`.
`SAVEPOINT name` / `ROLLBACK TO SAVEPOINT name` / `RELEASE SAVEPOINT name` give partial rollback. A PL/pgSQL `EXCEPTION` block uses one implicitly.
`BEGIN ISOLATION LEVEL … READ ONLY` (or `SET TRANSACTION …`) sets the transaction's characteristics.

### Isolation levels (Q11.06–Q11.09)
| Level | Snapshot taken | Prevents | You must handle |
|---|---|---|---|
| `READ COMMITTED` (default) | per **statement** | dirty reads | non-repeatable reads, lost updates (use locks or atomic updates) |
| `REPEATABLE READ` | once per **transaction** | + non-repeatable reads, phantoms | `40001 could not serialize… concurrent update` → **retry** |
| `SERIALIZABLE` | per transaction + conflict tracking | + write skew (all anomalies) | `40001` → **retry** |

PostgreSQL never allows dirty reads, so `READ UNCOMMITTED` behaves like `READ COMMITTED`.

### Row locks (Q11.10–Q11.14)
| Clause | Taken by | Blocks |
|---|---|---|
| `FOR UPDATE` | `DELETE`, key updates, explicit | every other row lock |
| `FOR NO KEY UPDATE` | ordinary `UPDATE` | `FOR UPDATE`, `FOR NO KEY UPDATE`, `FOR SHARE` |
| `FOR SHARE` | explicit | writers |
| `FOR KEY SHARE` | foreign-key checks | only `FOR UPDATE` (key changes and deletes) |

- `NOWAIT` raises an error instead of waiting (Q11.11).
- `SKIP LOCKED` silently skips locked rows. It's the standard pattern for **job queues** (Q11.13).
- **Readers never block writers and writers never block readers**, thanks to MVCC. Only writers block writers.

### Table and advisory locks, timeouts (Q11.15–Q11.17)
`LOCK TABLE t IN <mode> MODE` takes a table lock: `ACCESS SHARE` is the weakest and `ACCESS EXCLUSIVE` the strongest. DDL such as `ALTER TABLE` takes `ACCESS EXCLUSIVE`.
**Advisory locks** are locks on numbers whose meaning your application decides, for example "only one payout job". Session-level locks are released with `pg_advisory_unlock`, and `_xact_` locks at transaction end.
Protect production with `statement_timeout`, `lock_timeout` and `idle_in_transaction_session_timeout`. `SET LOCAL` applies a setting to the current transaction only.

### Watching and fixing (Q11.12, Q11.18–Q11.19)
- `pg_stat_activity`: one row per connection, with state, wait event and current query.
- `pg_locks` + `pg_blocking_pids(pid)`: who is waiting for whom.
- `pg_cancel_backend(pid)` stops a running query, and `pg_terminate_backend(pid)` closes a connection.

### Deadlocks (Q11.20)
A waits for B while B waits for A. After `deadlock_timeout`, a waiting backend checks for a cycle and cancels itself if it finds one.
To **prevent** deadlocks, lock rows in a consistent order (for example `ORDER BY id FOR UPDATE`) and keep transactions short.

### MVCC (Q11.21)
An `UPDATE` writes a **new row version**. Each version stores `xmin` (the creating transaction) and `xmax` (the deleting or locking transaction), and `ctid` is its physical location.
A snapshot decides which versions you can see. Old versions become "dead tuples" that `VACUUM` reclaims (ch14).

### Checkout design (Q11.23)
1. Reserve stock with a **conditional** update (`WHERE on_hand − reserved >= qty`), which is concurrency-safe.
2. Insert the order, its items and the payment, all in **one transaction**.
3. Keep slow external calls, such as the payment gateway, **outside** the transaction, or use a status machine (`pending → paid`).

## Two-terminal demos (do these by hand!)
Open two terminals and run `scripts/psql.sh` in each. They're called **A** and **B** below.
Use `playground_11.wallets` (create it by running queries.sql once).

**Demo 1: lost update (READ COMMITTED)**
```sql
-- A: BEGIN; SELECT balance FROM playground_11.wallets WHERE user_id=1;          -- say 1000
-- B: BEGIN; SELECT balance FROM playground_11.wallets WHERE user_id=1;          -- 1000
-- A: UPDATE playground_11.wallets SET balance = 1010 WHERE user_id=1; COMMIT;
-- B: UPDATE playground_11.wallets SET balance = 1010 WHERE user_id=1; COMMIT;   -- A's +10 is lost!
-- Fix: use SELECT … FOR UPDATE in both, or UPDATE … SET balance = balance + 10.
```
**Demo 2: FOR UPDATE blocks**
```sql
-- A: BEGIN; SELECT * FROM playground_11.wallets WHERE user_id=1 FOR UPDATE;
-- B: UPDATE playground_11.wallets SET balance = balance + 1 WHERE user_id=1;     -- hangs…
-- A: COMMIT;                                                                     -- …B continues
-- While B hangs, in a 3rd terminal: SELECT pid, pg_blocking_pids(pid), query FROM pg_stat_activity WHERE wait_event_type='Lock';
```
**Demo 3: SKIP LOCKED queue**
```sql
-- A: BEGIN; SELECT order_id FROM playground_11.packing_queue ORDER BY placed_at LIMIT 2 FOR UPDATE SKIP LOCKED;
-- B: BEGIN; SELECT order_id FROM playground_11.packing_queue ORDER BY placed_at LIMIT 2 FOR UPDATE SKIP LOCKED;  -- different rows
-- A, B: COMMIT;
```
**Demo 4: deadlock**
```sql
-- A: BEGIN; UPDATE playground_11.wallets SET balance=balance+1 WHERE user_id=1;
-- B: BEGIN; UPDATE playground_11.wallets SET balance=balance+1 WHERE user_id=2;
-- A: UPDATE playground_11.wallets SET balance=balance+1 WHERE user_id=2;   -- waits
-- B: UPDATE playground_11.wallets SET balance=balance+1 WHERE user_id=1;   -- ERROR: deadlock detected (after ~1s)
```
**Demo 5: serialization failure (write skew)**
```sql
-- A: BEGIN ISOLATION LEVEL SERIALIZABLE; SELECT count(*) FROM playground_11.on_call WHERE on_call;
-- B: BEGIN ISOLATION LEVEL SERIALIZABLE; SELECT count(*) FROM playground_11.on_call WHERE on_call;
-- A: UPDATE playground_11.on_call SET on_call=false WHERE agent='neha';  COMMIT;
-- B: UPDATE playground_11.on_call SET on_call=false WHERE agent='kabir'; -- ERROR 40001 → retry
-- Repeat with READ COMMITTED: both succeed and nobody is on call!
```

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `BEGIN`, `COMMIT` | start / finish a transaction | Q11.01 |
| `START TRANSACTION`, `ROLLBACK` | standard start / undo | Q11.02 |
| atomicity on error | an error undoes everything | Q11.03 |
| `SAVEPOINT`, `ROLLBACK TO SAVEPOINT`, `RELEASE SAVEPOINT` | partial rollback | Q11.04 |
| `ISOLATION LEVEL`, `READ ONLY`, `SHOW transaction_isolation` | transaction characteristics | Q11.05 |
| `READ COMMITTED` | per-statement snapshot | Q11.06 |
| `REPEATABLE READ` | per-transaction snapshot | Q11.07, Q11.08 |
| `serialization_failure` (40001) | retryable conflict | Q11.08, Q11.09 |
| `SERIALIZABLE` | prevents write skew | Q11.09 |
| `SELECT … FOR UPDATE`, `lock_timeout` | lock rows, bounded waiting | Q11.10 |
| `NOWAIT` | fail instead of waiting | Q11.11 |
| `pgrowlocks()`, `pg_locks` | inspect locks | Q11.12 |
| `SKIP LOCKED` | queue processing | Q11.13 |
| `FOR NO KEY UPDATE`, `FOR SHARE`, `FOR KEY SHARE` | weaker row locks | Q11.14 |
| `LOCK TABLE … IN … MODE` | table lock | Q11.15 |
| `pg_try_advisory_lock()`, `pg_advisory_unlock()`, `pg_advisory_xact_lock()` | application locks | Q11.16 |
| `statement_timeout`, `SET LOCAL`, `idle_in_transaction_session_timeout` | timeouts | Q11.17 |
| `pg_stat_activity` | session monitor | Q11.18 |
| `pg_cancel_backend()`, `pg_terminate_backend()` | stop a query or session | Q11.19 |
| deadlock, `deadlock_timeout`, `dblink_send_query()` | deadlock detection | Q11.20 |
| `xmin`, `xmax`, `ctid`, `pg_current_xact_id()` | MVCC internals | Q11.21 |
| `SET CONSTRAINTS … DEFERRED` | check constraints at commit | Q11.22 |
| checkout transaction | real-world transaction design | Q11.23 |

## Gotchas
- After an error inside `BEGIN`, psql reports "current transaction is aborted". Only `ROLLBACK` (or `ROLLBACK TO SAVEPOINT`) gets you out.
- Long-open transactions hold locks **and** stop `VACUUM` from cleaning dead rows. Never leave a session "idle in transaction".
- `REPEATABLE READ` and `SERIALIZABLE` require **retry logic** in the application.
- Read-then-write in `READ COMMITTED` loses updates. Use atomic `UPDATE … SET x = x + 1` or `FOR UPDATE`.
- DDL (`ALTER TABLE`) waits behind long transactions, and every later query queues behind the DDL. Set `lock_timeout` before running migrations.
- `now()` is the transaction start time. It's the same for every statement in the transaction.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/11_transactions_locking/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
