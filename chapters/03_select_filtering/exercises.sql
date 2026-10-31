-- =====================================================================
--  Chapter 03 · Exercises — SELECT & filtering
-- =====================================================================

-- [E03.01] (easy) List the 10 most expensive ACTIVE products in the 'Laptops' category
--          (category_id: look it up first in catalog.categories by slug = 'laptops').

-- [E03.02] (easy) Show users who signed up in the last 30 days, newest first, with their
--          phone or the text 'no phone'.

-- [E03.03] (easy) Find coupons that are inactive OR have no usage limit.

-- [E03.04] (medium) Find products whose name contains a model number like "Pro 42" or "Max 17"
--          (one of Pro/Max/Ultra followed by a space and 2 digits) using a regular expression.

-- [E03.05] (medium) Show orders from the last 90 days with a "size" label:
--          < ₹500 'small', < ₹5000 'medium', otherwise 'large'. Show 15 rows, biggest first.

-- [E03.06] (medium) List payments whose captured_at is NULL but whose status is not 'failed'
--          (what states are these?). Show the distinct statuses only.

-- [E03.07] (medium) For each product, show only its most recent price change from
--          catalog.price_history (one row per product). Limit 10.

-- [E03.08] (hard) Implement page 2 (rows 11-20) of "reviews sorted by helpful_count DESC, review_id DESC"
--          with OFFSET, and then the same page with keyset pagination given that page 1 ended
--          at helpful_count = 5 and review_id = 19000.

-- [E03.09] (hard) Users whose email domain is NOT one of gmail.com / yahoo.com / outlook.com,
--          written two ways: once with NOT IN + split_part (see ch04), once with a regex.
