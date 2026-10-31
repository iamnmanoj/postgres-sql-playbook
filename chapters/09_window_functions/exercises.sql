-- =====================================================================
--  Chapter 09 · Exercises — window functions
-- =====================================================================

-- [E09.01] (easy) Number each user's orders 1, 2, 3 … in the order they were placed (show user 2 only).

-- [E09.02] (easy) For every review of product 1, show the rating and the product's average rating.

-- [E09.03] (medium) The single most expensive product of every brand (use rank(); keep ties).

-- [E09.04] (medium) For each order of user 1, show grand_total and the running average of all orders so far.

-- [E09.05] (medium) Daily signups for the last 30 days with the difference vs. the previous day.

-- [E09.06] (medium) Split sellers into 4 quartiles by product count and show the min/max products per quartile.

-- [E09.07] (hard) For each shipment, the time between the order being placed and the first 'in_transit'
--          event; then the average per carrier. (lead/lag not required — think min() OVER or GROUP BY.)

-- [E09.08] (hard) Find users whose time between consecutive orders was ever more than 180 days
--          ("came back after 6 months"). Show user_id, the gap and the return date. Limit 10.

-- [E09.09] (hard) For each category, the 3-month moving average of monthly revenue (ROWS frame),
--          for Laptops only.
