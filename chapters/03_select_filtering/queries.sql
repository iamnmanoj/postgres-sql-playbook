-- =====================================================================
--  Chapter 03 · SELECT & filtering
--  Read-only chapter: nothing here changes data.
-- =====================================================================

-- =====================================================================
-- SECTION: Choosing columns
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q03.01] Every column of a few rows
-- Keywords: SELECT *, FROM, LIMIT
-- Business question: What does a warehouse record look like?
-- ---------------------------------------------------------------------
SELECT * FROM logistics.warehouses LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q03.02] Pick columns, rename them, and compute new ones
-- Keywords: column list, AS (alias), arithmetic expressions
-- Business question: Show each product's price including 18% GST.
-- ---------------------------------------------------------------------
SELECT sku,
       name                         AS product_name,
       base_price,
       base_price * 1.18            AS price_with_gst,
       base_price * 0.18            AS "GST amount"        -- double quotes allow spaces/case
FROM catalog.products
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q03.03] Glue text together
-- Keywords: || (concatenation), table alias
-- Business question: Build a one-line shipping label for addresses.
-- ---------------------------------------------------------------------
SELECT a.line1 || ', ' || a.city || ' - ' || a.postal_code AS label,
       a.line1 || ', ' || a.line2 AS with_line2                -- NULL || 'x' is NULL!
FROM core.addresses AS a
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q03.04] SELECT without a table
-- Keywords: SELECT expression, current_user, version()
-- ---------------------------------------------------------------------
SELECT 2 + 2 AS four, current_user, now() AS server_time, version();

-- =====================================================================
-- SECTION: Filtering rows with WHERE
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q03.05] Simple comparisons
-- Keywords: WHERE, =, <>, >, >=
-- Business question: Which products cost more than ₹1,00,000?
-- ---------------------------------------------------------------------
SELECT name, base_price
FROM catalog.products
WHERE base_price > 100000
ORDER BY base_price DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q03.06] Combine conditions — and mind the precedence (AND binds tighter than OR)
-- Keywords: AND, OR, NOT, parentheses
-- Business question: Active Prime users who are either from gmail OR never logged in.
-- ---------------------------------------------------------------------
SELECT user_id, email, last_login_at
FROM core.users
WHERE is_prime
  AND status = 'active'
  AND (email LIKE '%@gmail.com' OR last_login_at IS NULL)
  AND NOT (user_id <= 3)              -- exclude the admins
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q03.07] Match against a list
-- Keywords: IN, NOT IN
-- Business question: Orders that are still "in flight".
-- ---------------------------------------------------------------------
SELECT order_number, status, placed_at
FROM sales.orders
WHERE status IN ('paid', 'packed', 'shipped')
ORDER BY placed_at DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q03.08] The NOT IN + NULL trap
-- Keywords: NOT IN, NULL, three-valued logic
-- Note: x NOT IN (1, NULL) is never TRUE (it is NULL), so the whole row is filtered out.
-- ---------------------------------------------------------------------
SELECT 5 NOT IN (1, 2)        AS not_in_without_null,   -- true
       5 NOT IN (1, 2, NULL)  AS not_in_with_null,      -- NULL (unknown)!
       5 IN (5, NULL)         AS in_with_null;          -- true

-- ---------------------------------------------------------------------
-- [Q03.09] Ranges
-- Keywords: BETWEEN, NOT BETWEEN
-- Business question: Mid-range products (₹1,000 – ₹2,000 inclusive).
-- ---------------------------------------------------------------------
SELECT name, base_price
FROM catalog.products
WHERE base_price BETWEEN 1000 AND 2000           -- inclusive on both ends
  AND product_id NOT BETWEEN 1 AND 100
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q03.10] Time windows on timestamps (half-open is safest)
-- Keywords: >=, <, now(), interval
-- Business question: Orders placed in the last 24 hours.
-- ---------------------------------------------------------------------
SELECT order_number, status, placed_at
FROM sales.orders
WHERE placed_at >= now() - interval '24 hours'
  AND placed_at <  now()
ORDER BY placed_at DESC
LIMIT 10;

-- =====================================================================
-- SECTION: Pattern matching
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q03.11] Wildcards: % = any characters, _ = exactly one character
-- Keywords: LIKE, %, _
-- Business question: Find products whose SKU ends in '-V3' ... and product names starting with "Voltix".
-- ---------------------------------------------------------------------
SELECT sku FROM catalog.product_variants WHERE sku LIKE 'SKU-00010_-V3' LIMIT 5;
SELECT name FROM catalog.products WHERE name LIKE 'Voltix%' LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q03.12] Case-insensitive pattern
-- Keywords: ILIKE
-- Business question: Products mentioning "noise cancellation" in any letter case.
-- ---------------------------------------------------------------------
SELECT name, description
FROM catalog.products
WHERE description ILIKE '%NOISE CANCELLATION%'
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q03.13] Searching for a literal % or _
-- Keywords: LIKE … ESCAPE
-- Business question: Coupon descriptions containing a literal "%" sign.
-- ---------------------------------------------------------------------
SELECT code, description
FROM sales.coupons
WHERE description LIKE '%!%%' ESCAPE '!';     -- !% means a real percent sign
-- (none in the seed; try: SELECT 'Save 10% today' LIKE '%!%%' ESCAPE '!';)
SELECT 'Save 10% today' LIKE '%!%%' ESCAPE '!' AS has_percent_sign;

-- ---------------------------------------------------------------------
-- [Q03.14] SQL-standard regex-like patterns
-- Keywords: SIMILAR TO
-- Business question: Variant SKUs ending in V1 or V2.
-- ---------------------------------------------------------------------
SELECT sku FROM catalog.product_variants WHERE sku SIMILAR TO 'SKU-0000[0-9]{2}-V(1|2)' LIMIT 6;

-- ---------------------------------------------------------------------
-- [Q03.15] POSIX regular expressions
-- Keywords: ~, ~*, !~
-- Business question: Users whose names have double spaces or odd casing (data-quality check).
-- ---------------------------------------------------------------------
SELECT user_id, full_name
FROM core.users
WHERE full_name ~ '\s{2,}'                 -- ~  : case-sensitive match
   OR full_name !~ '^[A-Z][a-z]+ [A-Z]'     -- !~ : does NOT match
LIMIT 10;
SELECT count(*) AS outlook_users FROM core.users WHERE email ~* '@OUTLOOK\.COM$';   -- ~* : case-insensitive

-- =====================================================================
-- SECTION: NULL handling
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q03.16] Test for NULL (never use = NULL)
-- Keywords: IS NULL, IS NOT NULL
-- Business question: Users without a phone number but with a birthday on file.
-- ---------------------------------------------------------------------
SELECT user_id, full_name, phone, date_of_birth
FROM core.users
WHERE phone IS NULL AND date_of_birth IS NOT NULL
LIMIT 5;
SELECT count(*) FILTER (WHERE phone = NULL) AS wrong_way, count(*) FILTER (WHERE phone IS NULL) AS right_way
FROM core.users;

-- ---------------------------------------------------------------------
-- [Q03.17] NULL-safe comparison
-- Keywords: IS DISTINCT FROM, IS NOT DISTINCT FROM
-- Business question: Shipments whose delivery date differs from the estimate (treat NULL as a value).
-- ---------------------------------------------------------------------
SELECT shipment_id, estimated_delivery, delivered_at::date AS delivered_on
FROM logistics.shipments
WHERE delivered_at::date IS DISTINCT FROM estimated_delivery
LIMIT 5;
SELECT NULL = NULL AS equals_says, NULL IS NOT DISTINCT FROM NULL AS not_distinct_says;

-- ---------------------------------------------------------------------
-- [Q03.18] Replace NULL with a fallback
-- Keywords: COALESCE()
-- Business question: Show a contact number, falling back to "not provided".
-- ---------------------------------------------------------------------
SELECT full_name, COALESCE(phone::text, 'not provided') AS contact
FROM core.users
ORDER BY user_id
LIMIT 8;

-- ---------------------------------------------------------------------
-- [Q03.19] Turn a sentinel value into NULL (e.g. avoid division by zero)
-- Keywords: NULLIF()
-- Business question: Reserved-to-stock ratio, without crashing on zero stock.
-- ---------------------------------------------------------------------
SELECT variant_id, warehouse_id, quantity_reserved, quantity_on_hand,
       round(quantity_reserved::numeric / NULLIF(quantity_on_hand, 0), 2) AS reserved_ratio
FROM logistics.inventory
ORDER BY quantity_on_hand
LIMIT 5;

-- =====================================================================
-- SECTION: Conditional values
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q03.20] Searched CASE: bucket values
-- Keywords: CASE WHEN … THEN … ELSE … END
-- Business question: Label products as budget / mid-range / premium.
-- ---------------------------------------------------------------------
SELECT name, base_price,
       CASE WHEN base_price < 1000  THEN 'budget'
            WHEN base_price < 20000 THEN 'mid-range'
            ELSE 'premium' END AS price_band
FROM catalog.products
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q03.21] Simple CASE: map codes to labels
-- Keywords: CASE expr WHEN value
-- Business question: Show a customer-friendly label for each order status.
-- ---------------------------------------------------------------------
SELECT order_number,
       CASE status
           WHEN 'pending'   THEN 'Awaiting payment'
           WHEN 'paid'      THEN 'Payment received'
           WHEN 'delivered' THEN 'Delivered 🎉'
           ELSE initcap(status::text)
       END AS customer_label
FROM sales.orders
ORDER BY order_id DESC
LIMIT 8;

-- ---------------------------------------------------------------------
-- [Q03.22] Largest / smallest of several values in a row
-- Keywords: GREATEST(), LEAST()
-- Business question: Cap delivery fee at ₹49 but never below 0; pick the later of two timestamps.
-- ---------------------------------------------------------------------
SELECT order_number,
       LEAST(GREATEST(shipping_fee - 10, 0), 49) AS adjusted_fee,
       GREATEST(placed_at, updated_at)           AS last_activity
FROM sales.orders
LIMIT 5;

-- =====================================================================
-- SECTION: Sorting
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q03.23] Sort by several columns in different directions
-- Keywords: ORDER BY, ASC, DESC
-- Business question: Sellers: verified first, then best rated.
-- ---------------------------------------------------------------------
SELECT store_name, is_verified, rating_avg
FROM core.sellers
ORDER BY is_verified DESC, rating_avg DESC, store_name ASC
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q03.24] Control where NULLs go
-- Keywords: NULLS FIRST, NULLS LAST
-- Note: By default NULLs sort as if larger than any value (last in ASC, first in DESC).
-- Business question: Most recent logins first, never-logged-in users at the end.
-- ---------------------------------------------------------------------
SELECT user_id, last_login_at
FROM core.users
ORDER BY last_login_at DESC NULLS LAST
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q03.25] Sort by an expression, an alias, or a column position
-- Keywords: ORDER BY expression, ORDER BY alias, ORDER BY ordinal
-- Business question: Biggest discounts in rupees on recent orders.
-- ---------------------------------------------------------------------
SELECT order_number, subtotal, discount_total, discount_total / NULLIF(subtotal, 0) AS discount_share
FROM sales.orders
WHERE discount_total > 0
ORDER BY discount_share DESC, 3 DESC          -- alias, then 3rd column
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q03.26] ENUMs sort by their declared order, not alphabetically
-- Keywords: ORDER BY enum, enum comparison
-- Business question: Orders that have progressed at least to 'shipped'.
-- ---------------------------------------------------------------------
SELECT DISTINCT status FROM sales.orders WHERE status >= 'shipped' ORDER BY status;

-- =====================================================================
-- SECTION: Limiting & paging
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q03.27] Page 3 of results, 10 per page
-- Keywords: LIMIT, OFFSET
-- Note: OFFSET still reads and discards the skipped rows, so deep pages get slow (ch14).
-- ---------------------------------------------------------------------
SELECT product_id, name FROM catalog.products ORDER BY product_id LIMIT 10 OFFSET 20;

-- ---------------------------------------------------------------------
-- [Q03.28] SQL-standard syntax, including ties
-- Keywords: FETCH FIRST … ROWS ONLY, OFFSET … ROWS, WITH TIES
-- Business question: The 3 cheapest products, plus any others tied at the same price.
-- ---------------------------------------------------------------------
SELECT name, base_price FROM catalog.products ORDER BY base_price FETCH FIRST 3 ROWS ONLY;
SELECT name, base_price FROM catalog.products ORDER BY base_price OFFSET 3 ROWS FETCH NEXT 3 ROWS ONLY;  -- "page 2"
SELECT helpful_count, review_id FROM catalog.reviews ORDER BY helpful_count DESC FETCH FIRST 3 ROWS WITH TIES;

-- ---------------------------------------------------------------------
-- [Q03.29] Keyset ("seek") pagination with a row-constructor comparison
-- Keywords: row comparison (a, b) < (x, y)
-- Business question: Infinite scroll of orders: next 5 after the last one the app showed.
-- ---------------------------------------------------------------------
SELECT order_id, placed_at, order_number
FROM sales.orders
WHERE (placed_at, order_id) < (now() - interval '30 days', 999999999)   -- "after" the last seen row
ORDER BY placed_at DESC, order_id DESC
LIMIT 5;

-- =====================================================================
-- SECTION: Removing duplicates
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q03.30] Unique values / unique combinations
-- Keywords: DISTINCT
-- Business question: Which cities and states do we deliver to?
-- ---------------------------------------------------------------------
SELECT DISTINCT state, city FROM core.addresses ORDER BY state, city LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q03.31] Keep ONE row per group: the first by some ordering
-- Keywords: DISTINCT ON
-- Business question: Each user's most recent order.
-- ---------------------------------------------------------------------
SELECT DISTINCT ON (user_id) user_id, order_number, placed_at, grand_total
FROM sales.orders
ORDER BY user_id, placed_at DESC        -- ORDER BY must start with the DISTINCT ON columns
LIMIT 8;

-- =====================================================================
-- SECTION: Type-aware comparisons
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q03.32] citext makes comparisons case-insensitive automatically
-- Keywords: citext, =
-- Business question: Log in a user who typed their email in capitals.
-- ---------------------------------------------------------------------
SELECT user_id, email
FROM core.users
WHERE email = 'IRA.MEHTA1@SHOPSPHERE.TEST';          -- untyped literal becomes citext → matches
-- Gotcha: comparing citext with a value already typed as text uses text rules (case-sensitive):
SELECT count(*) AS matches_when_text
FROM core.users
WHERE email = upper('ira.mehta1@shopsphere.test');   -- upper() returns text → 0 rows

-- ---------------------------------------------------------------------
-- [Q03.33] Filtering on booleans and on enum sets
-- Keywords: boolean predicates, IS TRUE, IS NOT FALSE
-- Business question: Sellers whose verification flag is not false (true or unknown).
-- ---------------------------------------------------------------------
SELECT store_name, is_verified FROM core.sellers WHERE is_verified IS NOT FALSE LIMIT 3;
SELECT count(*) AS unverified FROM core.sellers WHERE NOT is_verified;
