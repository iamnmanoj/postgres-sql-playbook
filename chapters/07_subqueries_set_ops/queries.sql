-- =====================================================================
--  Chapter 07 · Subqueries & set operations
--  Read-only chapter.
-- =====================================================================

-- =====================================================================
-- SECTION: Scalar subqueries
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q07.01] A subquery that returns one value, used like a constant
-- Keywords: scalar subquery
-- Business question: Products priced above the average product price.
-- ---------------------------------------------------------------------
SELECT name, base_price
FROM catalog.products
WHERE base_price > (SELECT avg(base_price) FROM catalog.products)
ORDER BY base_price
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q07.02] Scalar subquery in the SELECT list
-- Keywords: scalar subquery in SELECT
-- Business question: Each brand's product count next to the overall total.
-- ---------------------------------------------------------------------
SELECT b.name,
       (SELECT count(*) FROM catalog.products p WHERE p.brand_id = b.brand_id) AS products,
       (SELECT count(*) FROM catalog.products)                                AS all_products
FROM catalog.brands b
ORDER BY products DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q07.03] A scalar subquery must return at most one row (otherwise: error)
-- Keywords: more than one row returned by a subquery
-- ---------------------------------------------------------------------
DO $$
BEGIN
    PERFORM (SELECT user_id FROM core.users WHERE is_prime);
EXCEPTION WHEN cardinality_violation THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

-- =====================================================================
-- SECTION: IN / NOT IN with subqueries
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q07.04] Filter by membership in a subquery result
-- Keywords: IN (subquery)
-- Business question: Users who have ever had a payment fail.
-- ---------------------------------------------------------------------
SELECT user_id, full_name
FROM core.users
WHERE user_id IN (SELECT o.user_id
                  FROM sales.orders o
                  JOIN sales.payments p ON p.order_id = o.order_id
                  WHERE p.status = 'failed')
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q07.05] NOT IN + a NULL in the subquery = no rows at all
-- Keywords: NOT IN (subquery), NULL trap
-- Business question: Users who never referred anyone (referred_by is NULL for ~80% of users!).
-- ---------------------------------------------------------------------
SELECT count(*) AS never_referred_anyone_notin
FROM core.users
WHERE user_id NOT IN (SELECT referred_by FROM core.users);                        -- NULL inside → 0 rows!
SELECT count(*) AS never_referred_anyone_fixed
FROM core.users
WHERE user_id NOT IN (SELECT referred_by FROM core.users WHERE referred_by IS NOT NULL);

-- =====================================================================
-- SECTION: Correlated subqueries & EXISTS
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q07.06] A correlated subquery runs (logically) once per outer row
-- Keywords: correlated subquery
-- Business question: Products priced above the average of THEIR OWN category.
-- ---------------------------------------------------------------------
SELECT p.name, p.base_price, p.category_id
FROM catalog.products p
WHERE p.base_price > (SELECT avg(p2.base_price)
                      FROM catalog.products p2
                      WHERE p2.category_id = p.category_id)   -- refers to the outer row
ORDER BY p.category_id, p.base_price DESC
LIMIT 8;

-- ---------------------------------------------------------------------
-- [Q07.07] Semi-join: "at least one related row exists"
-- Keywords: EXISTS
-- Business question: Sellers that have at least one product with a 1-star review.
-- ---------------------------------------------------------------------
SELECT s.seller_id, s.store_name
FROM core.sellers s
WHERE EXISTS (SELECT 1
              FROM catalog.products p
              JOIN catalog.reviews r ON r.product_id = p.product_id
              WHERE p.seller_id = s.seller_id AND r.rating = 1)
ORDER BY s.seller_id
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q07.08] Anti-join with NOT EXISTS (NULL-safe, usually the best choice)
-- Keywords: NOT EXISTS
-- Business question: Active users who have never placed an order — a re-engagement list.
-- ---------------------------------------------------------------------
SELECT u.user_id, u.email, u.created_at
FROM core.users u
WHERE u.status = 'active'
  AND NOT EXISTS (SELECT 1 FROM sales.orders o WHERE o.user_id = u.user_id)
ORDER BY u.created_at
LIMIT 5;
SELECT count(*) AS never_referred_anyone_not_exists          -- same answer as the "fixed" NOT IN, no NULL trap
FROM core.users u
WHERE NOT EXISTS (SELECT 1 FROM core.users r WHERE r.referred_by = u.user_id);

-- ---------------------------------------------------------------------
-- [Q07.09] Nested EXISTS: "for all" questions (relational division)
-- Keywords: NOT EXISTS … NOT EXISTS (double negation)
-- Business question: Users who have bought from EVERY one of three key brands (Voltix, Urbanloom, Cookwise).
-- ---------------------------------------------------------------------
SELECT u.user_id, u.full_name
FROM core.users u
WHERE NOT EXISTS (                                      -- there is no top brand …
    SELECT 1 FROM catalog.brands b
    WHERE b.name IN ('Voltix', 'Urbanloom', 'Cookwise')
      AND NOT EXISTS (                                  -- … that this user has NOT bought
          SELECT 1
          FROM sales.orders o
          JOIN sales.order_items oi ON oi.order_id = o.order_id
          JOIN catalog.product_variants v ON v.variant_id = oi.variant_id
          JOIN catalog.products p ON p.product_id = v.product_id
          WHERE o.user_id = u.user_id AND p.brand_id = b.brand_id))
LIMIT 5;

-- =====================================================================
-- SECTION: ANY / SOME / ALL
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q07.10] Compare with ANY value of a subquery
-- Keywords: = ANY, > ANY, SOME
-- Business question: How many products are cheaper than at least one Pixelon product? How many are in a men's category?
-- ---------------------------------------------------------------------
SELECT count(*) AS cheaper_than_some_pixelon
FROM catalog.products
WHERE base_price < ANY (SELECT p.base_price FROM catalog.products p JOIN catalog.brands b USING (brand_id) WHERE b.name = 'Pixelon');
SELECT count(*) AS same_as_in
FROM catalog.products
WHERE category_id = SOME (SELECT category_id FROM catalog.categories WHERE slug LIKE 'mens-%');   -- SOME = ANY

-- ---------------------------------------------------------------------
-- [Q07.11] Compare with ALL values
-- Keywords: > ALL, <> ALL
-- Business question: Laptops more expensive than EVERY tablet.
-- ---------------------------------------------------------------------
SELECT p.name, p.base_price
FROM catalog.products p
JOIN catalog.categories c USING (category_id)
WHERE c.slug = 'laptops'
  AND p.base_price > ALL (SELECT p2.base_price FROM catalog.products p2
                          JOIN catalog.categories c2 USING (category_id) WHERE c2.slug = 'tablets')
ORDER BY p.base_price
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q07.12] ANY / ALL with an array instead of a subquery
-- Keywords: = ANY(array), <> ALL(array)
-- Business question: Orders from a list of VIP user ids passed in by the app as one array parameter.
-- ---------------------------------------------------------------------
SELECT user_id, count(*) AS orders
FROM sales.orders
WHERE user_id = ANY (ARRAY[1, 2, 3, 42])
  AND status <> ALL (ARRAY['cancelled', 'refunded']::sales.order_status[])
GROUP BY user_id
ORDER BY user_id;

-- =====================================================================
-- SECTION: Derived tables & row subqueries
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q07.13] A subquery in FROM (derived table) — must have an alias
-- Keywords: derived table, subquery in FROM
-- Business question: Average delivered revenue per seller, but only over sellers with > ₹1 crore.
-- ---------------------------------------------------------------------
SELECT count(*) AS big_sellers, round(avg(revenue), 0) AS avg_revenue
FROM (
    SELECT oi.seller_id, sum(oi.line_total) AS revenue
    FROM sales.order_items oi
    JOIN sales.orders o USING (order_id)
    WHERE o.status = 'delivered'
    GROUP BY oi.seller_id
) AS seller_revenue
WHERE revenue > 10000000;

-- ---------------------------------------------------------------------
-- [Q07.14] Compare several columns at once against a subquery
-- Keywords: row subquery, (a, b) = (SELECT …), (a, b) IN (SELECT …)
-- Business question: Find the order(s) that match the single largest order's user and status.
-- ---------------------------------------------------------------------
SELECT order_number, user_id, status, grand_total
FROM sales.orders
WHERE (user_id, status) = (SELECT user_id, status FROM sales.orders ORDER BY grand_total DESC LIMIT 1)
ORDER BY grand_total DESC
LIMIT 5;
SELECT count(*) AS items_in_carts_that_were_also_ordered_by_same_user
FROM sales.cart_items ci JOIN sales.carts c USING (cart_id)
WHERE (c.user_id, ci.variant_id) IN (SELECT o.user_id, oi.variant_id
                                     FROM sales.orders o JOIN sales.order_items oi USING (order_id));

-- ---------------------------------------------------------------------
-- [Q07.15] Subquery in HAVING
-- Keywords: HAVING with subquery
-- Business question: Categories whose average rating beats the platform-wide average rating.
-- ---------------------------------------------------------------------
SELECT c.name, round(avg(r.rating), 3) AS avg_rating
FROM catalog.reviews r
JOIN catalog.products p USING (product_id)
JOIN catalog.categories c USING (category_id)
GROUP BY c.name
HAVING avg(r.rating) > (SELECT avg(rating) FROM catalog.reviews)
ORDER BY avg_rating DESC;

-- ---------------------------------------------------------------------
-- [Q07.16] Subquery in ORDER BY
-- Keywords: correlated subquery in ORDER BY
-- Business question: Sellers sorted by their newest product's listing date.
-- ---------------------------------------------------------------------
SELECT s.store_name
FROM core.sellers s
ORDER BY (SELECT max(p.created_at) FROM catalog.products p WHERE p.seller_id = s.seller_id) DESC NULLS LAST
LIMIT 5;

-- =====================================================================
-- SECTION: Set operations
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q07.17] Stack results and remove duplicates
-- Keywords: UNION
-- Business question: One contact list of all users who wrote a review OR asked for a return.
-- ---------------------------------------------------------------------
SELECT count(*) AS unique_people FROM (
    SELECT user_id FROM catalog.reviews
    UNION
    SELECT o.user_id FROM sales.returns r
    JOIN sales.order_items oi USING (order_item_id) JOIN sales.orders o USING (order_id)
) people;

-- ---------------------------------------------------------------------
-- [Q07.18] Stack results and KEEP duplicates (faster: no sort/hash for dedupe)
-- Keywords: UNION ALL
-- Business question: A unified activity feed for user 42: orders, reviews and notifications.
-- ---------------------------------------------------------------------
SELECT 'order' AS activity, order_number AS detail, placed_at AS at FROM sales.orders WHERE user_id = 42
UNION ALL
SELECT 'review', 'rated ' || rating || '★', created_at FROM catalog.reviews WHERE user_id = 42
UNION ALL
SELECT 'notification', template, sent_at FROM core.notifications WHERE user_id = 42
ORDER BY at DESC                       -- applies to the WHOLE union
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q07.19] Rows present in both results
-- Keywords: INTERSECT
-- Business question: Products that are both wish-listed AND sitting in someone's cart.
-- ---------------------------------------------------------------------
SELECT count(*) AS wished_and_carted FROM (
    SELECT product_id FROM sales.wishlists
    INTERSECT
    SELECT v.product_id FROM sales.cart_items ci JOIN catalog.product_variants v USING (variant_id)
) x;

-- ---------------------------------------------------------------------
-- [Q07.20] Rows in the first result but not the second
-- Keywords: EXCEPT
-- Business question: Products that were wish-listed but have never been ordered.
-- ---------------------------------------------------------------------
SELECT product_id FROM sales.wishlists
EXCEPT
SELECT v.product_id FROM sales.order_items oi JOIN catalog.product_variants v USING (variant_id)
ORDER BY product_id
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q07.21] Multiset versions keep duplicate counts
-- Keywords: INTERSECT ALL, EXCEPT ALL
-- Business question: How do duplicates behave? (bag/multiset semantics shown on tiny inline data)
-- ---------------------------------------------------------------------
SELECT x FROM (VALUES (1), (1), (1), (2)) a(x)
EXCEPT ALL
SELECT x FROM (VALUES (1), (2)) b(x);          -- → 1, 1  (one '1' removed per match)
SELECT x FROM (VALUES (1), (1), (2)) a(x)
INTERSECT ALL
SELECT x FROM (VALUES (1), (1), (1)) b(x);     -- → 1, 1

-- ---------------------------------------------------------------------
-- [Q07.22] Column types must line up; cast to make them compatible
-- Keywords: UNION type resolution, ::text, NULL::type
-- Business question: One "money movements" ledger from payments (+) and refunds (−).
-- ---------------------------------------------------------------------
SELECT 'payment' AS kind, payment_id AS ref, amount::numeric AS amount, method::text AS detail, created_at
FROM sales.payments WHERE status = 'captured' AND order_id = 500
UNION ALL
SELECT 'refund', refund_id, -amount, reason, created_at
FROM sales.refunds WHERE payment_id IN (SELECT payment_id FROM sales.payments WHERE order_id = 500)
UNION ALL
SELECT 'adjustment', NULL::bigint, 0, NULL, now()
ORDER BY created_at;

-- ---------------------------------------------------------------------
-- [Q07.23] Precedence: INTERSECT binds tighter than UNION/EXCEPT — use parentheses
-- Keywords: set-operation precedence, parentheses, LIMIT per branch
-- Business question: Top-3 priciest AND top-3 cheapest products in one list.
-- ---------------------------------------------------------------------
(SELECT name, base_price, 'priciest' AS kind FROM catalog.products ORDER BY base_price DESC LIMIT 3)
UNION ALL
(SELECT name, base_price, 'cheapest' FROM catalog.products ORDER BY base_price ASC LIMIT 3);
