-- =====================================================================
--  Chapter 06 · Exercises — joins
-- =====================================================================

-- [E06.01] (easy) List the 10 most recent reviews with product name, reviewer's full name and rating.

-- [E06.02] (easy) Show every warehouse with the total units on hand it stores (include warehouses with
--          no stock, showing 0).

-- [E06.03] (medium) Sellers who have products but have NEVER sold anything (no order_items rows).

-- [E06.04] (medium) For each order placed in the last 7 days show order_number, the shipping city,
--          the carrier and the shipment status (orders without a shipment must still appear).

-- [E06.05] (medium) Users who added something to their cart but never placed any order.

-- [E06.06] (medium) Each leaf category's best-selling product by units (use LATERAL).

-- [E06.07] (hard) For every order that used a coupon, check that the coupon was actually valid at
--          placed_at; return the orders where it was NOT (should be none — prove it).

-- [E06.08] (hard) Weekly orders for the last 8 weeks for channel 'app', with zero-filled weeks.

-- [E06.09] (hard) Pairs of users who were referred by the same referrer and signed up on the same day.
