-- =====================================================================
--  Chapter 11 · Exercises — transactions & locking
--  For two-session exercises open two terminals (scripts/psql.sh twice) and follow the README.
-- =====================================================================

-- [E11.01] (easy) In one transaction, move ₹100 from wallet 2 to wallet 3 in playground_11.wallets and
--          verify the total of all balances didn't change.

-- [E11.02] (easy) Use a savepoint: insert wallet 4 with balance 10, then try to insert wallet 4 again
--          (duplicate). Roll back only the failed part and commit the rest.
--          (In a script: use a DO block or ROLLBACK TO SAVEPOINT after the error.)

-- [E11.03] (medium) Write the "claim next job" query for a refunds worker: pick the oldest unprocessed refund
--          (processed_at IS NULL) without blocking on rows other workers hold, mark it processed, and return it.
--          Wrap it in BEGIN … ROLLBACK.

-- [E11.04] (medium) Make sure only one process at a time recalculates seller ratings using a transaction-level
--          advisory lock keyed by the text 'seller_ratings'. Show that the lock is visible in pg_locks.

-- [E11.05] (medium) Run a REPEATABLE READ, READ ONLY transaction that returns, from the SAME snapshot,
--          (a) the number of delivered orders and (b) the sum of their order_items line totals.

-- [E11.06] (hard) Two terminals: reproduce a lost update on playground_11.wallets with READ COMMITTED
--          (both read balance, both write balance+10 based on what they read), then fix it twice:
--          (1) with SELECT … FOR UPDATE, (2) with an atomic UPDATE … SET balance = balance + 10.

-- [E11.07] (hard) Show the xmin of wallet 1 before and after an UPDATE inside a transaction that you roll back.
--          What is xmax of the visible row afterwards, and why?
