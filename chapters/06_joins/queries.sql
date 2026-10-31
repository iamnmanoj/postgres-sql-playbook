-- =====================================================================
--  Chapter 06 · Joins
--  Read-only chapter.
-- =====================================================================

-- =====================================================================
-- SECTION: Inner joins
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q06.01] Combine two tables on matching keys
-- Keywords: INNER JOIN, ON
-- Business question: Show each product with its seller's store name.
-- ---------------------------------------------------------------------
SELECT p.name AS product, s.store_name
FROM catalog.products p
INNER JOIN core.sellers s ON s.seller_id = p.seller_id
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q06.02] The old comma syntax (implicit join) — avoid it in new code
-- Keywords: FROM a, b WHERE (implicit join)
-- Note: Forgetting the WHERE makes it a CROSS JOIN (every row × every row).
-- ---------------------------------------------------------------------
SELECT p.name, b.name AS brand
FROM catalog.products p, catalog.brands b
WHERE b.brand_id = p.brand_id
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q06.03] Join on a same-named column
-- Keywords: USING
-- Business question: Variant SKUs with their product names.
-- Note: USING (product_id) outputs the join column once.
-- ---------------------------------------------------------------------
SELECT product_id, v.sku, p.name
FROM catalog.product_variants v
JOIN catalog.products p USING (product_id)
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q06.04] NATURAL JOIN joins on ALL same-named columns — dangerous
-- Keywords: NATURAL JOIN
-- Note: orders and users share user_id, status AND updated_at; NATURAL JOIN silently uses
--       ALL of them. Here it even fails: orders.status (order_status) vs users.status (user_status).
-- ---------------------------------------------------------------------
DO $$
BEGIN
    PERFORM count(*) FROM sales.orders NATURAL JOIN core.users;
EXCEPTION WHEN undefined_function THEN
    RAISE NOTICE 'NATURAL JOIN failed: %', SQLERRM;
END $$;
SELECT count(*) AS natural_join_rows FROM catalog.products NATURAL JOIN catalog.product_variants;  -- joins on product_id AND sku AND is_active!
SELECT count(*) AS correct_join_rows FROM catalog.products JOIN catalog.product_variants USING (product_id);

-- ---------------------------------------------------------------------
-- [Q06.05] Chain many joins along foreign keys
-- Keywords: multi-table JOIN
-- Business question: A full order line: customer, product, brand, category, seller, warehouse city.
-- ---------------------------------------------------------------------
SELECT o.order_number, u.full_name AS customer, p.name AS product, b.name AS brand,
       c.name AS category, s.store_name, w.city AS shipped_from
FROM sales.orders o
JOIN core.users u                ON u.user_id = o.user_id
JOIN sales.order_items oi        ON oi.order_id = o.order_id
JOIN catalog.product_variants v  ON v.variant_id = oi.variant_id
JOIN catalog.products p          ON p.product_id = v.product_id
LEFT JOIN catalog.brands b       ON b.brand_id = p.brand_id
JOIN catalog.categories c        ON c.category_id = p.category_id
JOIN core.sellers s              ON s.seller_id = oi.seller_id
JOIN logistics.shipments sh      ON sh.order_id = o.order_id
JOIN logistics.warehouses w      ON w.warehouse_id = sh.warehouse_id
ORDER BY o.order_id DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q06.06] Join on a composite (multi-column) key
-- Keywords: JOIN ON a AND b
-- Business question: Stock movements with the current stock level of that variant in that warehouse.
-- ---------------------------------------------------------------------
SELECT m.movement_id, m.reason, m.change, i.quantity_on_hand, i.reorder_level
FROM logistics.inventory_movements m
JOIN logistics.inventory i
  ON i.variant_id = m.variant_id
 AND i.warehouse_id = m.warehouse_id
WHERE m.reason = 'adjustment'
LIMIT 5;

-- =====================================================================
-- SECTION: Outer joins
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q06.07] Keep all rows from the left side
-- Keywords: LEFT JOIN, LEFT OUTER JOIN
-- Business question: Every category with its number of products — including empty ones.
-- ---------------------------------------------------------------------
SELECT c.name, count(p.product_id) AS products      -- count(col) gives 0 for no matches
FROM catalog.categories c
LEFT OUTER JOIN catalog.products p ON p.category_id = c.category_id
GROUP BY c.category_id, c.name
ORDER BY products, c.name
LIMIT 8;

-- ---------------------------------------------------------------------
-- [Q06.08] Anti-join: rows with NO match
-- Keywords: LEFT JOIN … WHERE right.key IS NULL
-- Business question: Brands that have no products at all.
-- ---------------------------------------------------------------------
SELECT b.brand_id, b.name
FROM catalog.brands b
LEFT JOIN catalog.products p ON p.brand_id = b.brand_id
WHERE p.product_id IS NULL;

-- ---------------------------------------------------------------------
-- [Q06.09] The ON-vs-WHERE trap in outer joins
-- Keywords: LEFT JOIN, ON condition vs WHERE condition
-- Business question: For every seller, how many products are tagged 'bestseller'? (keep sellers with 0)
-- ---------------------------------------------------------------------
-- WRONG: the WHERE removes sellers with no matching product → turns into an inner join
SELECT count(*) AS sellers_listed_wrong FROM (
    SELECT s.seller_id
    FROM core.sellers s
    LEFT JOIN catalog.products p ON p.seller_id = s.seller_id
    WHERE 'bestseller' = ANY (p.tags)
    GROUP BY s.seller_id) x;
-- RIGHT: put the filter on the optional table into the ON clause
SELECT count(*) AS sellers_listed_right FROM (
    SELECT s.seller_id, count(p.product_id) AS bestsellers
    FROM core.sellers s
    LEFT JOIN catalog.products p ON p.seller_id = s.seller_id AND 'bestseller' = ANY (p.tags)
    GROUP BY s.seller_id) x;

-- ---------------------------------------------------------------------
-- [Q06.10] Keep all rows from the right side
-- Keywords: RIGHT JOIN
-- Business question: Every warehouse with the shipments sent in the last 2 days (warehouses with none too).
-- Note: a RIGHT JOIN b == b LEFT JOIN a; most people rewrite it as a LEFT JOIN.
-- ---------------------------------------------------------------------
SELECT w.code, count(sh.shipment_id) AS shipments_last_2_days
FROM logistics.shipments sh
RIGHT JOIN logistics.warehouses w
       ON w.warehouse_id = sh.warehouse_id AND sh.shipped_at >= now() - interval '2 days'
GROUP BY w.code
ORDER BY w.code;

-- ---------------------------------------------------------------------
-- [Q06.11] Keep unmatched rows from BOTH sides
-- Keywords: FULL OUTER JOIN, COALESCE()
-- Business question: Reconcile payouts vs. delivered sales for last month (find mismatches on either side).
-- ---------------------------------------------------------------------
WITH sales_last_month AS (
    SELECT oi.seller_id, sum(oi.line_total) AS gross
    FROM sales.order_items oi
    JOIN sales.orders o USING (order_id)
    WHERE o.status = 'delivered'
      AND o.placed_at >= date_trunc('month', now()) - interval '1 month'
      AND o.placed_at <  date_trunc('month', now())
    GROUP BY oi.seller_id
), payouts_last_month AS (
    SELECT seller_id, gross_sales
    FROM core.seller_payouts
    WHERE period = daterange((date_trunc('month', now()) - interval '1 month')::date, date_trunc('month', now())::date)
)
SELECT COALESCE(s.seller_id, p.seller_id) AS seller_id, s.gross AS computed, p.gross_sales AS paid_out,
       CASE WHEN s.seller_id IS NULL THEN 'payout without sales'
            WHEN p.seller_id IS NULL THEN 'sales without payout'
            WHEN s.gross <> p.gross_sales THEN 'amount mismatch'
            ELSE 'ok' END AS check_result
FROM sales_last_month s
FULL OUTER JOIN payouts_last_month p ON p.seller_id = s.seller_id
ORDER BY check_result, seller_id
LIMIT 10;

-- =====================================================================
-- SECTION: Self joins & cross joins
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q06.12] Join a table to itself (parent/child)
-- Keywords: self join, table aliases
-- Business question: Show each category with its parent and grandparent.
-- ---------------------------------------------------------------------
SELECT child.name AS category, parent.name AS parent, grandparent.name AS grandparent
FROM catalog.categories child
LEFT JOIN catalog.categories parent      ON parent.category_id = child.parent_id
LEFT JOIN catalog.categories grandparent ON grandparent.category_id = parent.parent_id
ORDER BY grandparent.name NULLS FIRST, parent.name NULLS FIRST, child.name
LIMIT 12;

-- ---------------------------------------------------------------------
-- [Q06.13] Self join on a "referred_by" relationship
-- Keywords: self join, aggregate
-- Business question: Top referrers and how many of their referrals became Prime.
-- ---------------------------------------------------------------------
SELECT referrer.user_id, referrer.full_name,
       count(*) AS referrals,
       count(*) FILTER (WHERE referee.is_prime) AS prime_referrals
FROM core.users referee
JOIN core.users referrer ON referrer.user_id = referee.referred_by
GROUP BY referrer.user_id, referrer.full_name
ORDER BY referrals DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q06.14] Self join to compare rows: pairs of products bought together
-- Keywords: self join, a.id < b.id (avoid duplicates/mirror pairs)
-- Business question: "Frequently bought together" — most common product pairs in the same order.
-- ---------------------------------------------------------------------
SELECT a.variant_id AS variant_a, b.variant_id AS variant_b, count(*) AS orders_together
FROM sales.order_items a
JOIN sales.order_items b ON b.order_id = a.order_id AND a.variant_id < b.variant_id
GROUP BY a.variant_id, b.variant_id
ORDER BY orders_together DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q06.15] Every combination of two sets
-- Keywords: CROSS JOIN
-- Business question: Build a warehouse × carrier matrix to fill in SLA targets.
-- ---------------------------------------------------------------------
SELECT w.code, c.carrier
FROM logistics.warehouses w
CROSS JOIN (SELECT DISTINCT carrier FROM logistics.shipments) c
ORDER BY w.code, c.carrier
LIMIT 10;

-- =====================================================================
-- SECTION: Non-equi joins
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q06.16] Join on a range condition
-- Keywords: non-equi join, BETWEEN in ON, VALUES
-- Business question: Classify every order into price bands defined in a small lookup list.
-- ---------------------------------------------------------------------
SELECT bands.band, count(*) AS orders
FROM sales.orders o
JOIN (VALUES ('micro', 0, 500), ('small', 500, 2000), ('medium', 2000, 10000), ('large', 10000, 100000), ('jumbo', 100000, 10000000))
     AS bands(band, low, high)
  ON o.grand_total >= bands.low AND o.grand_total < bands.high
GROUP BY bands.band, bands.low
ORDER BY bands.low;

-- ---------------------------------------------------------------------
-- [Q06.17] Join on range containment
-- Keywords: @> (range contains), tstzrange
-- Business question: Which coupons WERE valid at the moment each order was placed?
-- ---------------------------------------------------------------------
SELECT o.order_number, o.placed_at, c.code
FROM sales.orders o
JOIN sales.coupons c ON c.valid_during @> o.placed_at AND c.seller_id IS NULL
WHERE o.order_id BETWEEN 100 AND 102
ORDER BY o.order_number, c.code;

-- ---------------------------------------------------------------------
-- [Q06.18] Join to the price that was valid at a point in time
-- Keywords: non-equi join, inequality on timestamps, DISTINCT ON
-- Business question: For each price change, what was the previous price and when was it set? (as-of join)
-- ---------------------------------------------------------------------
SELECT DISTINCT ON (ph.price_history_id) ph.product_id, ph.changed_at, ph.new_price,
       prev.changed_at AS previous_change_at, prev.new_price AS previous_price
FROM catalog.price_history ph
LEFT JOIN catalog.price_history prev
       ON prev.product_id = ph.product_id AND prev.changed_at < ph.changed_at
WHERE ph.product_id IN (6, 12)
ORDER BY ph.price_history_id, prev.changed_at DESC;

-- =====================================================================
-- SECTION: LATERAL joins
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q06.19] Top-N per group with LATERAL
-- Keywords: JOIN LATERAL, ON true
-- Business question: Each seller's 3 most expensive products.
-- Note: LATERAL lets the subquery reference columns of tables to its left (s.seller_id).
-- ---------------------------------------------------------------------
SELECT s.store_name, top3.name, top3.base_price
FROM core.sellers s
JOIN LATERAL (
    SELECT p.name, p.base_price
    FROM catalog.products p
    WHERE p.seller_id = s.seller_id
    ORDER BY p.base_price DESC
    LIMIT 3
) top3 ON true
WHERE s.seller_id <= 3
ORDER BY s.store_name, top3.base_price DESC;

-- ---------------------------------------------------------------------
-- [Q06.20] LEFT JOIN LATERAL keeps rows even when the subquery returns nothing
-- Keywords: LEFT JOIN LATERAL
-- Business question: Each user's latest order (users without orders included, with NULLs).
-- ---------------------------------------------------------------------
SELECT u.user_id, u.full_name, last_order.order_number, last_order.placed_at
FROM core.users u
LEFT JOIN LATERAL (
    SELECT o.order_number, o.placed_at
    FROM sales.orders o
    WHERE o.user_id = u.user_id
    ORDER BY o.placed_at DESC
    LIMIT 1
) last_order ON true
ORDER BY u.user_id DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q06.21] LATERAL with a set-returning function
-- Keywords: CROSS JOIN LATERAL, unnest()
-- Business question: Count products per tag (explode the tags array).
-- ---------------------------------------------------------------------
SELECT t.tag, count(*) AS products
FROM catalog.products p
CROSS JOIN LATERAL unnest(p.tags) AS t(tag)
GROUP BY t.tag
ORDER BY products DESC;

-- =====================================================================
-- SECTION: Joining to generated rows
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q06.22] Fill gaps in a time series with generate_series + LEFT JOIN
-- Keywords: generate_series(), LEFT JOIN, COALESCE()
-- Business question: Daily refunds for the last 14 days — show 0 on days without refunds.
-- ---------------------------------------------------------------------
SELECT d::date AS day, COALESCE(r.refunds, 0) AS refunds, COALESCE(r.amount, 0) AS amount
FROM generate_series(current_date - 13, current_date, interval '1 day') AS d
LEFT JOIN (
    SELECT created_at::date AS day, count(*) AS refunds, sum(amount) AS amount
    FROM sales.refunds
    GROUP BY 1
) r ON r.day = d::date
ORDER BY day;

-- ---------------------------------------------------------------------
-- [Q06.23] Join to an inline VALUES list
-- Keywords: JOIN (VALUES …)
-- Business question: Apply regional shipping surcharges from a small rate card.
-- ---------------------------------------------------------------------
SELECT a.state, count(*) AS orders, rate.surcharge, count(*) * rate.surcharge AS surcharge_total
FROM sales.orders o
JOIN core.addresses a ON a.address_id = o.shipping_address_id
JOIN (VALUES ('Assam', 40), ('Odisha', 25), ('Kerala', 20)) AS rate(state, surcharge)
  ON rate.state = a.state
GROUP BY a.state, rate.surcharge
ORDER BY surcharge_total DESC;

-- ---------------------------------------------------------------------
-- [Q06.24] Join with an aggregated subquery (avoid row multiplication)
-- Keywords: JOIN (subquery), pre-aggregation
-- Business question: Products with their units sold AND their review count — without double counting.
-- ---------------------------------------------------------------------
SELECT p.name, COALESCE(s.units, 0) AS units_sold, COALESCE(r.reviews, 0) AS reviews
FROM catalog.products p
LEFT JOIN (SELECT v.product_id, sum(oi.quantity) AS units
           FROM sales.order_items oi JOIN catalog.product_variants v USING (variant_id)
           GROUP BY v.product_id) s ON s.product_id = p.product_id
LEFT JOIN (SELECT product_id, count(*) AS reviews FROM catalog.reviews GROUP BY product_id) r
       ON r.product_id = p.product_id
ORDER BY units_sold DESC
LIMIT 5;
