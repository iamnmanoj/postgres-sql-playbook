-- =====================================================================
--  Chapter 03 · Solutions — SELECT & filtering
-- =====================================================================

-- [E03.01] Top active laptops
-- Keywords: WHERE, subquery for lookup, ORDER BY, LIMIT
SELECT name, base_price
FROM catalog.products
WHERE is_active
  AND category_id = (SELECT category_id FROM catalog.categories WHERE slug = 'laptops')
ORDER BY base_price DESC
LIMIT 10;

-- [E03.02] Recent sign-ups
-- Keywords: interval, COALESCE(), ORDER BY DESC
SELECT user_id, full_name, created_at, COALESCE(phone::text, 'no phone') AS phone
FROM core.users
WHERE created_at >= now() - interval '30 days'
ORDER BY created_at DESC;

-- [E03.03] Inactive or unlimited coupons
-- Keywords: OR, IS NULL, NOT
SELECT code, is_active, usage_limit
FROM sales.coupons
WHERE NOT is_active OR usage_limit IS NULL;

-- [E03.04] Model numbers via regex
-- Keywords: ~, regex character classes
SELECT name
FROM catalog.products
WHERE name ~ '(Pro|Max|Ultra) [0-9]{2}$'
LIMIT 10;

-- [E03.05] Order size label
-- Keywords: CASE, ORDER BY, interval
SELECT order_number, grand_total,
       CASE WHEN grand_total < 500 THEN 'small'
            WHEN grand_total < 5000 THEN 'medium'
            ELSE 'large' END AS size_label
FROM sales.orders
WHERE placed_at >= now() - interval '90 days'
ORDER BY grand_total DESC
LIMIT 15;

-- [E03.06] Uncaptured non-failed payments
-- Keywords: IS NULL, <>, DISTINCT
SELECT DISTINCT status
FROM sales.payments
WHERE captured_at IS NULL AND status <> 'failed';

-- [E03.07] Latest price change per product
-- Keywords: DISTINCT ON, ORDER BY
SELECT DISTINCT ON (product_id) product_id, old_price, new_price, changed_at
FROM catalog.price_history
ORDER BY product_id, changed_at DESC
LIMIT 10;

-- [E03.08] OFFSET page vs keyset page
-- Keywords: OFFSET, LIMIT, row comparison
SELECT review_id, helpful_count
FROM catalog.reviews
ORDER BY helpful_count DESC, review_id DESC
LIMIT 10 OFFSET 10;

SELECT review_id, helpful_count
FROM catalog.reviews
WHERE (helpful_count, review_id) < (5, 19000)
ORDER BY helpful_count DESC, review_id DESC
LIMIT 10;

-- [E03.09] Non-mainstream email domains, two ways
-- Keywords: NOT IN, split_part(), !~*
SELECT email FROM core.users
WHERE split_part(email::text, '@', 2) NOT IN ('gmail.com', 'yahoo.com', 'outlook.com')
LIMIT 5;

SELECT email FROM core.users
WHERE email !~* '@(gmail|yahoo|outlook)\.com$'
LIMIT 5;
