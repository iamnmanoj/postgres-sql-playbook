-- =====================================================================
--  Chapter 11 · Transactions, isolation & locking
--  Concurrency needs TWO sessions. This script uses the dblink extension to
--  open a second connection ("session B") so the demos run unattended.
--  The README has the same scenarios as step-by-step two-terminal exercises.
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS dblink;
CREATE EXTENSION IF NOT EXISTS pgrowlocks;          -- shows row-level locks of a table

DROP SCHEMA IF EXISTS playground_11 CASCADE;
CREATE SCHEMA playground_11;
CREATE TABLE playground_11.wallets (
    user_id bigint PRIMARY KEY,
    balance numeric(12, 2) NOT NULL CHECK (balance >= 0)
);
INSERT INTO playground_11.wallets VALUES (1, 1000), (2, 500), (3, 0);

-- helper: (re)open session B
SELECT dblink_disconnect(c) FROM unnest(dblink_get_connections()) AS c;
SELECT dblink_connect('session_b', format('dbname=%s user=postgres', current_database()));

-- =====================================================================
-- SECTION: Transaction basics
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q11.01] Group statements so they succeed or fail together (atomicity)
-- Keywords: BEGIN, COMMIT
-- Business question: Move ₹200 of wallet credit from user 1 to user 2.
-- ---------------------------------------------------------------------
BEGIN;
UPDATE playground_11.wallets SET balance = balance - 200 WHERE user_id = 1;
UPDATE playground_11.wallets SET balance = balance + 200 WHERE user_id = 2;
COMMIT;
SELECT * FROM playground_11.wallets ORDER BY user_id;

-- ---------------------------------------------------------------------
-- [Q11.02] Undo everything since BEGIN
-- Keywords: START TRANSACTION, ROLLBACK
-- ---------------------------------------------------------------------
START TRANSACTION;                                     -- same as BEGIN
UPDATE playground_11.wallets SET balance = 0;           -- oops, no WHERE!
SELECT sum(balance) AS during_mistake FROM playground_11.wallets;
ROLLBACK;
SELECT sum(balance) AS after_rollback FROM playground_11.wallets;

-- ---------------------------------------------------------------------
-- [Q11.03] A failed statement aborts the whole transaction (all-or-nothing)
-- Keywords: atomicity, CHECK violation, transaction aborted
-- Business question: Transfer more than the balance → nothing must change.
-- Note: In psql, after an error every later statement fails with
--       "current transaction is aborted" until ROLLBACK. Here a DO block shows it.
-- ---------------------------------------------------------------------
DO $$
BEGIN
    UPDATE playground_11.wallets SET balance = balance + 5000 WHERE user_id = 3;   -- succeeds...
    UPDATE playground_11.wallets SET balance = balance - 5000 WHERE user_id = 1;   -- ...violates CHECK
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Transfer failed, both updates undone: %', SQLERRM;
END $$;
SELECT * FROM playground_11.wallets WHERE user_id IN (1, 3) ORDER BY user_id;

-- ---------------------------------------------------------------------
-- [Q11.04] Partial rollback inside a transaction
-- Keywords: SAVEPOINT, ROLLBACK TO SAVEPOINT, RELEASE SAVEPOINT
-- Business question: Apply a coupon; if the coupon step fails, keep the rest of the checkout.
-- ---------------------------------------------------------------------
BEGIN;
UPDATE playground_11.wallets SET balance = balance - 100 WHERE user_id = 2;    -- step 1 (keep)
SAVEPOINT before_coupon;
UPDATE playground_11.wallets SET balance = balance + 999 WHERE user_id = 2;    -- step 2 (bad)
ROLLBACK TO SAVEPOINT before_coupon;                                           -- undo only step 2
SAVEPOINT bonus;
UPDATE playground_11.wallets SET balance = balance + 10 WHERE user_id = 2;     -- step 3 (keep)
RELEASE SAVEPOINT bonus;                                                       -- forget the savepoint, keep work
COMMIT;
SELECT * FROM playground_11.wallets WHERE user_id = 2;                         -- 700 - 100 + 10 = 610

-- ---------------------------------------------------------------------
-- [Q11.05] Transaction characteristics
-- Keywords: SET TRANSACTION, ISOLATION LEVEL, READ ONLY, SHOW transaction_isolation
-- Business question: A consistent, read-only snapshot for a finance report.
-- ---------------------------------------------------------------------
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SHOW transaction_isolation;
SHOW transaction_read_only;
SELECT count(*) AS orders, sum(grand_total) AS gmv FROM sales.orders WHERE status = 'delivered';
DO $$
BEGIN
    UPDATE playground_11.wallets SET balance = 0;
EXCEPTION WHEN read_only_sql_transaction THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;
COMMIT;

-- =====================================================================
-- SECTION: Isolation levels in action
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q11.06] READ COMMITTED (default): each statement sees the latest committed data
-- Keywords: READ COMMITTED, non-repeatable read
-- ---------------------------------------------------------------------
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT balance AS first_read FROM playground_11.wallets WHERE user_id = 3;
SELECT dblink_exec('session_b', 'UPDATE playground_11.wallets SET balance = balance + 50 WHERE user_id = 3');  -- B commits
SELECT balance AS second_read_sees_change FROM playground_11.wallets WHERE user_id = 3;
COMMIT;

-- ---------------------------------------------------------------------
-- [Q11.07] REPEATABLE READ: the whole transaction sees ONE snapshot
-- Keywords: REPEATABLE READ, snapshot
-- ---------------------------------------------------------------------
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT balance AS first_read FROM playground_11.wallets WHERE user_id = 3;
SELECT dblink_exec('session_b', 'UPDATE playground_11.wallets SET balance = balance + 50 WHERE user_id = 3');
SELECT balance AS second_read_unchanged FROM playground_11.wallets WHERE user_id = 3;
COMMIT;
SELECT balance AS after_commit FROM playground_11.wallets WHERE user_id = 3;

-- ---------------------------------------------------------------------
-- [Q11.08] REPEATABLE READ refuses to overwrite a row changed after its snapshot
-- Keywords: could not serialize access due to concurrent update, serialization_failure
-- Note: The application must RETRY the whole transaction on SQLSTATE 40001.
-- ---------------------------------------------------------------------
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT balance FROM playground_11.wallets WHERE user_id = 3;          -- snapshot taken here
SELECT dblink_exec('session_b', 'UPDATE playground_11.wallets SET balance = balance + 1 WHERE user_id = 3');
DO $$
BEGIN
    UPDATE playground_11.wallets SET balance = balance + 1 WHERE user_id = 3;
EXCEPTION WHEN serialization_failure THEN
    RAISE NOTICE 'Expected error (retry needed): %', SQLERRM;
END $$;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q11.09] SERIALIZABLE prevents "write skew"
-- Keywords: SERIALIZABLE, write skew, could not serialize access due to read/write dependencies
-- Business question: Rule: at least one support agent must stay on call. Two agents go off call at once.
-- ---------------------------------------------------------------------
CREATE TABLE playground_11.on_call (agent text PRIMARY KEY, on_call boolean NOT NULL);
INSERT INTO playground_11.on_call VALUES ('neha', true), ('kabir', true);

SELECT dblink_exec('session_b', 'BEGIN ISOLATION LEVEL SERIALIZABLE');
SELECT * FROM dblink('session_b', 'SELECT count(*) FROM playground_11.on_call WHERE on_call') AS t(on_call_seen_by_b bigint);
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS on_call_seen_by_a FROM playground_11.on_call WHERE on_call;     -- 2 → "safe" to leave
UPDATE playground_11.on_call SET on_call = false WHERE agent = 'neha';
COMMIT;
DO $$
BEGIN
    PERFORM dblink_exec('session_b', 'UPDATE playground_11.on_call SET on_call = false WHERE agent = ''kabir''');
    PERFORM dblink_exec('session_b', 'COMMIT');
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Session B rejected: %', SQLERRM;          -- fails on its UPDATE (or at COMMIT)
END $$;
SELECT dblink_exec('session_b', 'ROLLBACK');
SELECT * FROM playground_11.on_call ORDER BY agent;                                -- kabir is still on call

-- =====================================================================
-- SECTION: Row locks
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q11.10] Lock rows you are about to change (prevents lost updates)
-- Keywords: SELECT … FOR UPDATE, lock_timeout
-- Business question: While we process user 1's wallet, another session can't change it.
-- ---------------------------------------------------------------------
BEGIN;
SELECT * FROM playground_11.wallets WHERE user_id = 1 FOR UPDATE;
DO $$
BEGIN
    PERFORM dblink_exec('session_b', 'SET lock_timeout = ''300ms''');
    PERFORM dblink_exec('session_b', 'UPDATE playground_11.wallets SET balance = 0 WHERE user_id = 1');
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Session B blocked by our lock: %', SQLERRM;
END $$;
UPDATE playground_11.wallets SET balance = balance - 50 WHERE user_id = 1;
COMMIT;
SELECT dblink_exec('session_b', 'RESET lock_timeout');

-- ---------------------------------------------------------------------
-- [Q11.11] Don't wait for a lock: fail immediately
-- Keywords: FOR UPDATE NOWAIT, lock_not_available
-- Business question: The admin UI should say "order is being edited by someone else".
-- ---------------------------------------------------------------------
SELECT dblink_exec('session_b', 'BEGIN');
SELECT * FROM dblink('session_b', 'SELECT user_id FROM playground_11.wallets WHERE user_id = 2 FOR UPDATE') AS t(locked_by_b bigint);
DO $$
BEGIN
    PERFORM 1 FROM playground_11.wallets WHERE user_id = 2 FOR UPDATE NOWAIT;
EXCEPTION WHEN lock_not_available THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- [Q11.12] Inspect who holds which row locks
-- Keywords: pgrowlocks(), pg_locks, pg_blocking_pids()
-- ---------------------------------------------------------------------
SELECT locked_row, modes, pids FROM pgrowlocks('playground_11.wallets');
SELECT locktype, relation::regclass, mode, granted, pid
FROM pg_locks
WHERE relation = 'playground_11.wallets'::regclass;
SELECT dblink_exec('session_b', 'ROLLBACK');

-- ---------------------------------------------------------------------
-- [Q11.13] A work queue: many workers, no double-processing, no waiting
-- Keywords: FOR UPDATE SKIP LOCKED
-- Business question: Several packing-station workers grab the next orders to pack.
-- ---------------------------------------------------------------------
CREATE TABLE playground_11.packing_queue AS
SELECT order_id, placed_at FROM sales.orders WHERE status = 'paid' ORDER BY placed_at LIMIT 10;
SELECT dblink_exec('session_b', 'BEGIN');
SELECT * FROM dblink('session_b',
    'SELECT order_id FROM playground_11.packing_queue ORDER BY placed_at LIMIT 3 FOR UPDATE SKIP LOCKED')
    AS t(worker_b_took bigint);
BEGIN;
SELECT order_id AS worker_a_took
FROM playground_11.packing_queue
ORDER BY placed_at
LIMIT 3
FOR UPDATE SKIP LOCKED;                    -- gets the NEXT three, not B's
COMMIT;
SELECT dblink_exec('session_b', 'ROLLBACK');

-- ---------------------------------------------------------------------
-- [Q11.14] Weaker row-lock modes
-- Keywords: FOR NO KEY UPDATE, FOR SHARE, FOR KEY SHARE
-- Note: FOR KEY SHARE (taken by FK checks) only conflicts with key changes/deletes;
--       FOR NO KEY UPDATE (taken by normal UPDATEs) lets FK inserts in child tables proceed.
-- ---------------------------------------------------------------------
BEGIN;
SELECT user_id FROM playground_11.wallets WHERE user_id = 1 FOR NO KEY UPDATE;
SELECT user_id FROM playground_11.wallets WHERE user_id = 2 FOR SHARE;
SELECT user_id FROM playground_11.wallets WHERE user_id = 3 FOR KEY SHARE;
SELECT locked_row, modes FROM pgrowlocks('playground_11.wallets');
COMMIT;

-- =====================================================================
-- SECTION: Table locks, advisory locks, timeouts, sessions
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q11.15] Explicit table locks
-- Keywords: LOCK TABLE … IN … MODE
-- Business question: Freeze a table against writes while computing a month-end snapshot.
-- ---------------------------------------------------------------------
BEGIN;
LOCK TABLE playground_11.wallets IN SHARE MODE;          -- others can read, not write
SELECT mode, granted FROM pg_locks
WHERE relation = 'playground_11.wallets'::regclass AND pid = pg_backend_pid();
COMMIT;

-- ---------------------------------------------------------------------
-- [Q11.16] Advisory locks: application-defined mutexes
-- Keywords: pg_try_advisory_lock(), pg_advisory_unlock(), pg_advisory_xact_lock(), hashtext()
-- Business question: Ensure only one instance of the nightly payout job runs.
-- ---------------------------------------------------------------------
SELECT pg_try_advisory_lock(hashtext('nightly_payout_job')) AS a_got_lock;
SELECT * FROM dblink('session_b', 'SELECT pg_try_advisory_lock(hashtext(''nightly_payout_job''))') AS t(b_got_lock boolean);
SELECT pg_advisory_unlock(hashtext('nightly_payout_job')) AS a_released;
BEGIN;
SELECT pg_advisory_xact_lock(42);                         -- released automatically at COMMIT/ROLLBACK
COMMIT;

-- ---------------------------------------------------------------------
-- [Q11.17] Timeouts that protect the database
-- Keywords: statement_timeout, lock_timeout, idle_in_transaction_session_timeout, SET LOCAL
-- ---------------------------------------------------------------------
BEGIN;
SET LOCAL statement_timeout = '200ms';                    -- only for this transaction
DO $$
BEGIN
    PERFORM pg_sleep(1);
EXCEPTION WHEN query_canceled THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;
COMMIT;
SHOW idle_in_transaction_session_timeout;                 -- 0 = disabled; set e.g. '5min' in production

-- ---------------------------------------------------------------------
-- [Q11.18] Who is connected and what are they doing?
-- Keywords: pg_stat_activity, wait_event, state, backend_xid
-- ---------------------------------------------------------------------
SELECT pid, usename, application_name, state, wait_event_type, wait_event,
       now() - xact_start AS xact_age, left(query, 60) AS query
FROM pg_stat_activity
WHERE datname = current_database()
ORDER BY pid;

-- ---------------------------------------------------------------------
-- [Q11.19] Cancel a query or kill a session
-- Keywords: pg_cancel_backend(), pg_terminate_backend()
-- ---------------------------------------------------------------------
SELECT dblink_connect('victim', format('dbname=%s user=postgres', current_database()));
SELECT pid AS victim_pid FROM dblink('victim', 'SELECT pg_backend_pid()') AS t(pid int) \gset
SELECT pg_cancel_backend(:victim_pid)    AS cancel_sent;    -- cancels the running query (if any)
SELECT pg_terminate_backend(:victim_pid) AS terminated;     -- closes the whole connection
SELECT dblink_disconnect('victim');

-- ---------------------------------------------------------------------
-- [Q11.20] Deadlock: two sessions wait for each other → PostgreSQL kills one
-- Keywords: deadlock detected, deadlock_timeout, dblink_send_query(), dblink_get_result()
-- Note: After waiting deadlock_timeout (default 1s) a blocked backend checks for a cycle and,
--       if it finds one, cancels ITSELF. We give A a long timeout so B (waiting first) is the victim.
-- ---------------------------------------------------------------------
BEGIN;
SET LOCAL deadlock_timeout = '10s';
UPDATE playground_11.wallets SET balance = balance + 1 WHERE user_id = 1;           -- A locks row 1
SELECT dblink_exec('session_b', 'BEGIN');
SELECT dblink_exec('session_b', 'UPDATE playground_11.wallets SET balance = balance + 1 WHERE user_id = 2');  -- B locks row 2
SELECT dblink_send_query('session_b', 'UPDATE playground_11.wallets SET balance = balance + 1 WHERE user_id = 1');  -- B waits for A
SELECT pg_sleep(0.2);
UPDATE playground_11.wallets SET balance = balance + 1 WHERE user_id = 2;           -- A waits for B → cycle! (~1s)
COMMIT;                                                                             -- A survived
SELECT * FROM dblink_get_result('session_b', false) AS t(b_result text);            -- false = report, don't raise
SELECT dblink_error_message('session_b') AS b_error;                                -- "deadlock detected"
SELECT * FROM dblink_get_result('session_b', false) AS t(b_result text);            -- drain (async results end with an empty set)
SELECT dblink_exec('session_b', 'ROLLBACK');

-- =====================================================================
-- SECTION: MVCC internals & deferred constraints
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q11.21] Every row version carries transaction ids
-- Keywords: xmin, xmax, ctid, pg_current_xact_id(), MVCC
-- Note: UPDATE writes a NEW row version (new ctid, new xmin); the old one is cleaned by VACUUM.
-- ---------------------------------------------------------------------
SELECT ctid, xmin, xmax, * FROM playground_11.wallets WHERE user_id = 3;
BEGIN;
SELECT pg_current_xact_id() AS my_xid;
UPDATE playground_11.wallets SET balance = balance + 1 WHERE user_id = 3;
SELECT ctid, xmin, xmax, * FROM playground_11.wallets WHERE user_id = 3;           -- new ctid, xmin = my_xid
COMMIT;

-- ---------------------------------------------------------------------
-- [Q11.22] Defer constraint checks to COMMIT
-- Keywords: SET CONSTRAINTS … DEFERRED, DEFERRABLE INITIALLY IMMEDIATE
-- Business question: Swap the "primary" flag between two wallets without a transient violation.
-- ---------------------------------------------------------------------
CREATE TABLE playground_11.primary_wallet (
    slot    int PRIMARY KEY,
    user_id bigint NOT NULL,
    CONSTRAINT primary_wallet_user_unique UNIQUE (user_id) DEFERRABLE INITIALLY IMMEDIATE
);
INSERT INTO playground_11.primary_wallet VALUES (1, 1), (2, 2);
BEGIN;
SET CONSTRAINTS playground_11.primary_wallet_user_unique DEFERRED;
UPDATE playground_11.primary_wallet SET user_id = 2 WHERE slot = 1;    -- temporarily duplicate!
UPDATE playground_11.primary_wallet SET user_id = 1 WHERE slot = 2;
COMMIT;                                                               -- checked here: OK
SELECT * FROM playground_11.primary_wallet ORDER BY slot;

-- =====================================================================
-- SECTION: A real checkout transaction
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q11.23] Checkout: reserve stock → create order → items → payment, atomically
-- Keywords: transaction design, conditional UPDATE for stock, RETURNING … INTO psql vars (\gset)
-- Business question: User 21 buys 2 units of variant 9 from whichever warehouse has stock.
-- Note: The conditional UPDATE is concurrency-safe: two buyers can't both take the last unit.
-- ---------------------------------------------------------------------
BEGIN;
-- 1) reserve stock in the warehouse with the most available units (row lock held until COMMIT)
UPDATE logistics.inventory i
SET quantity_reserved = quantity_reserved + 2, updated_at = now()
WHERE (variant_id, warehouse_id) = (
        SELECT variant_id, warehouse_id FROM logistics.inventory
        WHERE variant_id = 9 AND quantity_on_hand - quantity_reserved >= 2
        ORDER BY quantity_on_hand - quantity_reserved DESC
        LIMIT 1
        FOR UPDATE)
RETURNING warehouse_id AS reserved_in_warehouse;
-- 2) create the order
INSERT INTO sales.orders (order_number, user_id, shipping_address_id, status)
SELECT 'SS-' || to_char(now(), 'YYYYMMDD') || '-DEMO', 21, address_id, 'pending'
FROM core.addresses WHERE user_id = 21 AND is_default
RETURNING order_id AS new_order_id \gset
-- 3) add the line item at the current price
INSERT INTO sales.order_items (order_id, variant_id, seller_id, quantity, unit_price)
SELECT :new_order_id, v.variant_id, p.seller_id, 2, p.base_price + v.price_delta
FROM catalog.product_variants v JOIN catalog.products p USING (product_id)
WHERE v.variant_id = 9;
-- 4) totals + payment
UPDATE sales.orders SET subtotal = (SELECT sum(line_total) FROM sales.order_items WHERE order_id = :new_order_id)
WHERE order_id = :new_order_id;
INSERT INTO sales.payments (order_id, method, status, amount)
SELECT order_id, 'upi', 'initiated', grand_total FROM sales.orders WHERE order_id = :new_order_id
RETURNING payment_id, amount;
ROLLBACK;     -- in the real app: COMMIT

SELECT dblink_disconnect('session_b');
