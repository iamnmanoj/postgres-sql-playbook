-- =====================================================================
--  Chapter 07 · Exercises — subqueries & set operations
-- =====================================================================

-- [E07.01] (easy) The single most expensive order: order_number and grand_total, using a scalar
--          subquery with max() (not ORDER BY/LIMIT).

-- [E07.02] (easy) Products that have at least one review with images (image_urls not empty), via EXISTS.

-- [E07.03] (medium) Variants that are NOT stocked in any warehouse, using NOT EXISTS.

-- [E07.04] (medium) For each user, show their number of orders as a correlated scalar subquery, but
--          only users with more orders than the average user (subquery in WHERE on a derived table).

-- [E07.05] (medium) Coupon codes that have never been redeemed, written with EXCEPT.

-- [E07.06] (medium) Users who both wrote a 5-star review and requested a return (INTERSECT on user_id).

-- [E07.07] (hard) The most recent order of each user whose grand_total is larger than ALL of that
--          user's previous orders ("new personal record" orders). Show 10.

-- [E07.08] (hard) One list of "things that need attention": stale pending orders older than 2 days,
--          lost shipments, and returns still 'requested' after 5 days — columns: kind, ref_id, since.
