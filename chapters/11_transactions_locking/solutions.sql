-- =====================================================================
--  Chapter 11 · Solutions — transactions & locking
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS playground_11;
CREATE TABLE IF NOT EXISTS playground_11.wallets (
    user_id bigint PRIMARY KEY,
    balance numeric(12, 2) NOT NULL CHECK (balance >= 0)
);
INSERT INTO playground_11.wallets VALUES (1, 1000), (2, 500), (3, 0) ON CONFLICT DO NOTHING;
DELETE FROM playground_11.wallets WHERE user_id = 4;

-- [E11.01] Atomic transfer
-- Keywords: BEGIN, COMMIT
SELECT sum(balance) AS total_before FROM playground_11.wallets;
BEGIN;
UPDATE playground_11.wallets SET balance = balance - 100 WHERE user_id = 2;
UPDATE playground_11.wallets SET balance = balance + 100 WHERE user_id = 3;
COMMIT;
SELECT sum(balance) AS total_after FROM playground_11.wallets;

-- [E11.02] Savepoint around a failing statement
-- Keywords: SAVEPOINT, ROLLBACK TO SAVEPOINT (here emulated by a DO block's implicit savepoint)
BEGIN;
INSERT INTO playground_11.wallets VALUES (4, 10);
DO $$
BEGIN
    INSERT INTO playground_11.wallets VALUES (4, 10);           -- duplicate key
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'Duplicate ignored (the block rolled back to its implicit savepoint)';
END $$;
COMMIT;
SELECT * FROM playground_11.wallets WHERE user_id = 4;
-- Interactive psql version:
--   BEGIN; INSERT … (4,10); SAVEPOINT s; INSERT … (4,10);  -- ERROR
--   ROLLBACK TO SAVEPOINT s; COMMIT;

-- [E11.03] Claim the next refund job
-- Keywords: FOR UPDATE SKIP LOCKED, UPDATE … RETURNING
BEGIN;
UPDATE sales.refunds
SET processed_at = now()
WHERE refund_id = (SELECT refund_id FROM sales.refunds
                   WHERE processed_at IS NULL
                   ORDER BY created_at
                   LIMIT 1
                   FOR UPDATE SKIP LOCKED)
RETURNING refund_id, amount, reason;
ROLLBACK;

-- [E11.04] Transaction-level advisory lock
-- Keywords: pg_advisory_xact_lock(), hashtext(), pg_locks
BEGIN;
SELECT pg_advisory_xact_lock(hashtext('seller_ratings'));
SELECT locktype, objid, mode, granted FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid();
COMMIT;

-- [E11.05] Consistent read-only snapshot
-- Keywords: REPEATABLE READ, READ ONLY
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT count(*) AS delivered_orders FROM sales.orders WHERE status = 'delivered';
SELECT sum(oi.line_total) AS delivered_items_total
FROM sales.order_items oi JOIN sales.orders o USING (order_id) WHERE o.status = 'delivered';
COMMIT;

-- [E11.06] Lost update (two terminals) — see README "Demo 1"; the safe single-statement version:
-- Keywords: atomic UPDATE, FOR UPDATE
BEGIN;
SELECT balance FROM playground_11.wallets WHERE user_id = 1 FOR UPDATE;   -- fix 1: lock while deciding
UPDATE playground_11.wallets SET balance = balance + 10 WHERE user_id = 1;  -- fix 2: atomic increment
COMMIT;

-- [E11.07] xmin / xmax after a rolled-back update
-- Keywords: xmin, xmax, ROLLBACK, MVCC
SELECT xmin, xmax, balance FROM playground_11.wallets WHERE user_id = 1;
BEGIN;
UPDATE playground_11.wallets SET balance = balance + 1 WHERE user_id = 1;
ROLLBACK;
SELECT xmin, xmax, balance FROM playground_11.wallets WHERE user_id = 1;
-- xmin is unchanged (same row version is still the visible one). xmax now holds the id of the
-- aborted transaction that tried to update/lock the row; since that transaction aborted, the row is
-- still live. The new version it created is dead and will be removed by VACUUM.
