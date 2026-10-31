-- =====================================================================
--  Chapter 20 · Exercises — advanced extras
-- =====================================================================

-- [E20.01] (medium) For every coupon, show whether its validity window overlaps the next 30 days, using a
--          tstzrange and the && operator.

-- [E20.02] (medium) For seller 85 build a datemultirange of all payout periods with range_agg and show its
--          lower and upper bound.

-- [E20.03] (easy) Take a 5% BERNOULLI sample of order_items and estimate the share of items with a discount.

-- [E20.04] (medium) Using the system catalogs, list every table in the catalog schema with its number of
--          columns and its number of indexes.

-- [E20.05] (medium) Use a cursor to fetch the 5 newest reviews, then the next 5 (two FETCH commands).

-- [E20.06] (hard) Use crosstab() to pivot review counts: one row per rating (1-5) and two columns,
--          'with_body' and 'without_body' (whether the review has a body text).
