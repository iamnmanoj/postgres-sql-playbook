-- =====================================================================
--  Chapter 12 · Exercises — JSONB & arrays
-- =====================================================================

-- [E12.01] (easy) Count orders per metadata->>'device'.

-- [E12.02] (easy) List the 5 products with the most tags, showing the tags as a comma-separated string.

-- [E12.03] (medium) For failed payments, count failures per gateway_response error_code.

-- [E12.04] (medium) Find users whose preferences say newsletter = true AND push notifications = true,
--          using a single @> containment test.

-- [E12.05] (medium) Show the most common fashion materials (attributes->>'material') among products
--          whose 'care' array contains "machine wash".

-- [E12.06] (medium) Inside BEGIN … ROLLBACK, add a key "loyalty_tier": "gold" to preferences of every
--          Prime user, and remove the "theme" key for everyone. Return how many rows changed.

-- [E12.07] (hard) Using JSON_TABLE, produce one row per (product, connectivity option) and count products
--          per (option, warranty_months).

-- [E12.08] (hard) Products whose tags overlap with the tags of product 1 but are not product 1 itself,
--          ranked by number of shared tags.

-- [E12.09] (hard) Build one JSON document per seller with: store name, rating, and an array of their
--          3 most expensive products as objects {name, price}. Show 3 sellers.
