-- =====================================================================
--  Chapter 05 · Exercises — aggregation & grouping
-- =====================================================================

-- [E05.01] (easy) How many products does each brand have? Include the brand name; biggest first.

-- [E05.02] (easy) Total refunded amount per refund reason. Only reasons with more than 50 refunds.

-- [E05.03] (medium) For each warehouse: number of variants stocked, total units on hand, total units
--          reserved, and the % of on-hand units that are reserved (2 decimals).

-- [E05.04] (medium) For every month of the last 12, count new users and how many of them are Prime,
--          in one query using FILTER.

-- [E05.05] (medium) The median and average rating of each brand with at least 200 reviews.

-- [E05.06] (medium) For each order status, list the distinct payment methods used (as an array).

-- [E05.07] (hard) Seller leaderboard JSON: one JSON object mapping store_name → delivered revenue
--          for the top 5 sellers.

-- [E05.08] (hard) A report of delivered revenue by category ROOT (Electronics, Fashion, …) and leaf
--          category with ROLLUP subtotals per root and a grand total.
--          Hint: join categories twice (leaf → parent → maybe grandparent); keep it to 3 levels.

-- [E05.09] (hard) Coupon effectiveness: per coupon code, redemptions, total discount, average discount,
--          and the share of all coupon discount it accounts for (percent, 1 decimal).
