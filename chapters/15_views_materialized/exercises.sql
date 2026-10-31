-- =====================================================================
--  Chapter 15 · Exercises — views & materialized views
--  Create your objects in schema reporting with prefix ex15_.
-- =====================================================================

-- [E15.01] (easy) Create a view reporting.ex15_product_catalog with product name, brand name, leaf category
--          name, seller store name and price, for active products only. Query the 5 cheapest laptops from it.

-- [E15.02] (medium) Create an updatable view over core.addresses that shows only Karnataka addresses, with
--          LOCAL CHECK OPTION. Show that moving an address to 'Kerala' through the view fails.

-- [E15.03] (medium) Create a materialized view reporting.ex15_product_ratings (product_id, reviews, avg_rating),
--          add the index needed for CONCURRENTLY, and refresh it concurrently.

-- [E15.04] (medium) Using the materialized view from E15.03, list the 5 best-rated products with at least 20 reviews.

-- [E15.05] (hard) Write a query that lists every view and materialized view in the reporting schema with
--          its kind ('view' / 'materialized view') and its size on disk.
