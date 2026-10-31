-- =====================================================================
--  Chapter 16 · Exercises — functions, procedures & PL/pgSQL
--  Create your objects in schema app with prefix ex16_.
-- =====================================================================

-- [E16.01] (easy) Write an IMMUTABLE SQL function app.ex16_with_gst(price numeric) returning price incl. 18% GST,
--          rounded to 2 decimals. Use it on 3 products.

-- [E16.02] (easy) Write a STABLE SQL function app.ex16_product_rating(p_product_id bigint) returning the
--          average rating (2 decimals) or NULL if there are no reviews.

-- [E16.03] (medium) Write a set-returning function app.ex16_orders_between(p_from date, p_to date) that returns
--          (day date, orders bigint, gmv numeric) for every day in the range, including days with 0 orders.

-- [E16.04] (medium) Write a PL/pgSQL function app.ex16_loyalty_tier(p_user_id bigint) returning 'platinum',
--          'gold', 'silver' or 'bronze' based on delivered lifetime value (≥10L, ≥3L, ≥50k), raising an
--          exception with a HINT if the user doesn't exist.

-- [E16.05] (hard) Write a procedure app.ex16_reprice_brand(p_brand text, p_pct numeric) that changes base_price
--          of all the brand's products by p_pct percent, inserts a price_history row for each, and reports the
--          number of products changed with RAISE NOTICE. Call it inside BEGIN … ROLLBACK.

-- [E16.06] (hard) Write a function that receives a table name from catalog/sales and returns its row count
--          and total size, using dynamic SQL with format('%I').
