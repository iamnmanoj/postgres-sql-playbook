-- =====================================================================
--  Chapter 08 · Exercises — CTEs & recursion
-- =====================================================================

-- [E08.01] (easy) With a CTE, compute each brand's average rating, then list brands above 3.9.

-- [E08.02] (medium) Chain three CTEs: (1) orders in the last 180 days, (2) per-user order counts,
--          (3) users with 3+ orders; finally show how many such repeat buyers exist per city
--          (default address).

-- [E08.03] (medium) Recursive: list all LEAF categories (no children) under 'Fashion' with their full
--          path like 'Fashion / Men / Jeans'.

-- [E08.04] (medium) Recursive: generate the numbers 1..12 and use them to show each month name
--          (to_char(make_date(2025, n, 1), 'Month')).

-- [E08.05] (hard) For user 108, list every user in their referral downline with the level
--          (1 = direct referral), using SEARCH DEPTH FIRST so children appear under parents.

-- [E08.06] (hard) In ONE statement (inside BEGIN … ROLLBACK): cancel all 'pending' orders older than
--          30 days, and insert an order_status_history row for each one, returning how many were cancelled.
