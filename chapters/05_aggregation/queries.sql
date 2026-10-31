-- =====================================================================
--  Chapter 05 · Aggregation & grouping
--  Read-only chapter.
-- =====================================================================

-- =====================================================================
-- SECTION: Aggregate functions over the whole table
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q05.01] Three kinds of count
-- Keywords: count(*), count(column), count(DISTINCT …)
-- Business question: How many users, how many gave a phone number, how many distinct cities?
-- ---------------------------------------------------------------------
SELECT count(*)                          AS users,            -- counts rows
       count(phone)                      AS with_phone,       -- counts non-NULL values
       count(DISTINCT referred_by)       AS distinct_referrers
FROM core.users;

-- ---------------------------------------------------------------------
-- [Q05.02] The core numeric aggregates
-- Keywords: sum(), avg(), min(), max()
-- Business question: Lifetime GMV, average order value, smallest and largest order.
-- ---------------------------------------------------------------------
SELECT sum(grand_total)            AS gmv,
       round(avg(grand_total), 2)  AS avg_order_value,
       min(grand_total)            AS smallest_order,
       max(grand_total)            AS largest_order,
       min(placed_at)              AS first_order_at,     -- min/max work on dates & text too
       max(placed_at)              AS last_order_at
FROM sales.orders
WHERE status = 'delivered';

-- ---------------------------------------------------------------------
-- [Q05.03] Aggregates over zero rows: count gives 0, the rest give NULL
-- Keywords: empty set, COALESCE()
-- Business question: Revenue from the (empty) smartwatches category.
-- ---------------------------------------------------------------------
SELECT count(*)                  AS items_sold,
       sum(oi.line_total)        AS revenue_raw,               -- NULL!
       COALESCE(sum(oi.line_total), 0) AS revenue
FROM sales.order_items oi
JOIN catalog.product_variants v ON v.variant_id = oi.variant_id
JOIN catalog.products p ON p.product_id = v.product_id
JOIN catalog.categories c ON c.category_id = p.category_id
WHERE c.slug = 'smartwatches';

-- =====================================================================
-- SECTION: GROUP BY & HAVING
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q05.04] One row per group
-- Keywords: GROUP BY
-- Business question: How many orders are in each status?
-- ---------------------------------------------------------------------
SELECT status, count(*) AS orders, sum(grand_total) AS value
FROM sales.orders
GROUP BY status
ORDER BY orders DESC;

-- ---------------------------------------------------------------------
-- [Q05.05] Group by several columns
-- Keywords: GROUP BY col1, col2
-- Business question: Payment method × status breakdown.
-- ---------------------------------------------------------------------
SELECT method, status, count(*) AS payments
FROM sales.payments
GROUP BY method, status
ORDER BY method, status;

-- ---------------------------------------------------------------------
-- [Q05.06] Group by an expression (and refer to it by position)
-- Keywords: GROUP BY expression, GROUP BY ordinal, date_trunc()
-- Business question: Monthly GMV for the last 12 months.
-- ---------------------------------------------------------------------
SELECT date_trunc('month', placed_at)::date AS month,
       count(*)                             AS orders,
       sum(grand_total)                     AS gmv
FROM sales.orders
WHERE status NOT IN ('cancelled', 'pending')
  AND placed_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- [Q05.07] Filter GROUPS (not rows) with HAVING
-- Keywords: HAVING
-- Business question: Loyal customers: more than 20 delivered orders.
-- ---------------------------------------------------------------------
SELECT user_id, count(*) AS delivered_orders, sum(grand_total) AS lifetime_value
FROM sales.orders
WHERE status = 'delivered'          -- row filter: before grouping
GROUP BY user_id
HAVING count(*) > 20                -- group filter: after grouping
ORDER BY delivered_orders DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q05.08] Grouping by the primary key lets you select other columns of that table
-- Keywords: functional dependency, GROUP BY primary key
-- Business question: Number of products per seller, with the store name.
-- ---------------------------------------------------------------------
SELECT s.seller_id, s.store_name, s.is_verified, count(p.product_id) AS products
FROM core.sellers s
JOIN catalog.products p ON p.seller_id = s.seller_id
GROUP BY s.seller_id                  -- store_name & is_verified depend on the PK
ORDER BY products DESC
LIMIT 5;

-- =====================================================================
-- SECTION: Conditional aggregation
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q05.09] Several conditional counts in one pass
-- Keywords: FILTER (WHERE …)
-- Business question: Per carrier: delivered, in transit, lost, returned shipments.
-- ---------------------------------------------------------------------
SELECT carrier,
       count(*) FILTER (WHERE status = 'delivered')                         AS delivered,
       count(*) FILTER (WHERE status IN ('in_transit', 'out_for_delivery')) AS moving,
       count(*) FILTER (WHERE status = 'lost')                              AS lost,
       count(*) FILTER (WHERE status = 'returned')                          AS returned
FROM logistics.shipments
GROUP BY carrier
ORDER BY carrier;

-- ---------------------------------------------------------------------
-- [Q05.10] Pivot rows into columns with CASE inside an aggregate (portable SQL)
-- Keywords: sum(CASE …), pivot
-- Business question: Revenue by payment method as columns, per quarter.
-- ---------------------------------------------------------------------
SELECT to_char(date_trunc('quarter', p.created_at), 'YYYY-"Q"Q') AS quarter,
       sum(CASE WHEN p.method = 'upi'  THEN p.amount ELSE 0 END) AS upi,
       sum(CASE WHEN p.method = 'card' THEN p.amount ELSE 0 END) AS card,
       sum(CASE WHEN p.method = 'cod'  THEN p.amount ELSE 0 END) AS cod,
       sum(CASE WHEN p.method IN ('wallet', 'netbanking') THEN p.amount ELSE 0 END) AS other
FROM sales.payments p
WHERE p.status = 'captured'
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- [Q05.11] Ratios from conditional aggregates
-- Keywords: avg(boolean::int), FILTER, percentage
-- Business question: Per carrier: % of shipments lost and % delivered on or before the estimate.
-- ---------------------------------------------------------------------
SELECT carrier,
       round(100.0 * count(*) FILTER (WHERE status = 'lost') / count(*), 2) AS pct_lost,
       round(100 * avg((delivered_at::date <= estimated_delivery)::int), 1) AS pct_on_time
FROM logistics.shipments
GROUP BY carrier
ORDER BY pct_on_time DESC;

-- =====================================================================
-- SECTION: Aggregates that build strings, arrays and JSON
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q05.12] Concatenate values of a group, in a chosen order
-- Keywords: string_agg(), ORDER BY inside aggregate, DISTINCT inside aggregate
-- Business question: For each order, a single line listing its product names.
-- ---------------------------------------------------------------------
SELECT oi.order_id,
       string_agg(p.name, ' + ' ORDER BY p.name)   AS products,
       string_agg(DISTINCT c.name, ', ')            AS categories
FROM sales.order_items oi
JOIN catalog.product_variants v ON v.variant_id = oi.variant_id
JOIN catalog.products p ON p.product_id = v.product_id
JOIN catalog.categories c ON c.category_id = p.category_id
GROUP BY oi.order_id
HAVING count(*) >= 4
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q05.13] Collect values into an array
-- Keywords: array_agg()
-- Business question: Which warehouses stock each variant (as an array)?
-- ---------------------------------------------------------------------
SELECT i.variant_id, array_agg(w.code ORDER BY w.code) AS warehouses, sum(i.quantity_on_hand) AS total_stock
FROM logistics.inventory i
JOIN logistics.warehouses w USING (warehouse_id)
GROUP BY i.variant_id
ORDER BY i.variant_id
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q05.14] Build JSON documents from groups
-- Keywords: json_agg(), jsonb_agg(), jsonb_object_agg(), jsonb_build_object()
-- Business question: An API response: each order with its items as JSON, and status counts as a JSON object.
-- ---------------------------------------------------------------------
SELECT o.order_number,
       jsonb_agg(jsonb_build_object('variant', oi.variant_id, 'qty', oi.quantity, 'price', oi.unit_price)
                 ORDER BY oi.order_item_id) AS items
FROM sales.orders o
JOIN sales.order_items oi USING (order_id)
WHERE o.order_id IN (10, 11)
GROUP BY o.order_number;
SELECT jsonb_object_agg(status, cnt) AS status_counts,
       json_agg(status ORDER BY cnt DESC) AS statuses_by_popularity
FROM (SELECT status, count(*) AS cnt FROM sales.orders GROUP BY status) s;

-- =====================================================================
-- SECTION: Boolean & statistical aggregates
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q05.15] Did ALL / ANY row in the group satisfy a condition?
-- Keywords: bool_and(), bool_or(), every()
-- Business question: Per seller: are all products active? Is any product premium-tagged?
-- ---------------------------------------------------------------------
SELECT seller_id,
       bool_and(is_active)              AS all_active,
       every(base_price > 0)            AS all_priced,          -- SQL-standard name of bool_and
       bool_or('premium' = ANY (tags))  AS has_premium
FROM catalog.products
GROUP BY seller_id
ORDER BY seller_id
LIMIT 8;

-- ---------------------------------------------------------------------
-- [Q05.16] Spread of values
-- Keywords: stddev(), stddev_pop(), variance()
-- Business question: How volatile are order values per channel?
-- ---------------------------------------------------------------------
SELECT metadata->>'channel' AS channel,
       round(avg(grand_total), 0)        AS avg_value,
       round(stddev(grand_total), 0)     AS stddev_sample,
       round(stddev_pop(grand_total), 0) AS stddev_population,
       round(variance(grand_total), 0)   AS variance
FROM sales.orders
GROUP BY 1;

-- ---------------------------------------------------------------------
-- [Q05.17] Correlation and linear regression
-- Keywords: corr(), regr_slope(), regr_intercept(), regr_r2()
-- Business question: Do pricier products get worse ratings?
-- ---------------------------------------------------------------------
SELECT round(corr(p.base_price, r.rating)::numeric, 4)            AS correlation,
       round(regr_slope(r.rating, p.base_price)::numeric * 10000, 6) AS rating_change_per_10k_rupees,
       round(regr_intercept(r.rating, p.base_price)::numeric, 3)  AS intercept,
       round(regr_r2(r.rating, p.base_price)::numeric, 5)         AS r_squared
FROM catalog.reviews r
JOIN catalog.products p USING (product_id);

-- =====================================================================
-- SECTION: Ordered-set & hypothetical-set aggregates (WITHIN GROUP)
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q05.18] Median and percentiles
-- Keywords: percentile_cont(), percentile_disc(), WITHIN GROUP
-- Business question: Median and 90th percentile order value per channel.
-- ---------------------------------------------------------------------
SELECT metadata->>'channel' AS channel,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY grand_total)  AS median_interpolated,
       percentile_disc(0.5) WITHIN GROUP (ORDER BY grand_total)  AS median_actual_value,
       percentile_cont(ARRAY[0.25, 0.75, 0.9]) WITHIN GROUP (ORDER BY grand_total) AS p25_p75_p90
FROM sales.orders
GROUP BY 1;

-- ---------------------------------------------------------------------
-- [Q05.19] Most frequent value
-- Keywords: mode() WITHIN GROUP
-- Business question: What's the most common review rating per category?
-- ---------------------------------------------------------------------
SELECT c.name AS category, mode() WITHIN GROUP (ORDER BY r.rating) AS most_common_rating, count(*) AS reviews
FROM catalog.reviews r
JOIN catalog.products p USING (product_id)
JOIN catalog.categories c USING (category_id)
GROUP BY c.name
ORDER BY reviews DESC
LIMIT 8;

-- ---------------------------------------------------------------------
-- [Q05.20] "Where would this value rank?" — hypothetical-set aggregates
-- Keywords: rank() WITHIN GROUP, percent_rank() WITHIN GROUP
-- Business question: If a new laptop is priced ₹75,000, where does it rank among laptops by price?
-- ---------------------------------------------------------------------
SELECT rank(75000) WITHIN GROUP (ORDER BY p.base_price)          AS rank_if_inserted,
       round(percent_rank(75000) WITHIN GROUP (ORDER BY p.base_price)::numeric, 3) AS percentile,
       count(*) AS laptops
FROM catalog.products p
JOIN catalog.categories c USING (category_id)
WHERE c.slug = 'laptops';

-- =====================================================================
-- SECTION: Multi-level summaries
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q05.21] Several GROUP BYs in one query
-- Keywords: GROUPING SETS
-- Business question: Order counts by channel, by device, and the grand total — in one result.
-- ---------------------------------------------------------------------
SELECT metadata->>'channel' AS channel, metadata->>'device' AS device, count(*) AS orders
FROM sales.orders
GROUP BY GROUPING SETS ((metadata->>'channel'), (metadata->>'device'), ())
ORDER BY channel NULLS LAST, device NULLS LAST;

-- ---------------------------------------------------------------------
-- [Q05.22] Hierarchical subtotals
-- Keywords: ROLLUP, GROUPING()
-- Business question: Revenue by year → quarter, with yearly subtotals and a grand total.
-- ---------------------------------------------------------------------
SELECT CASE WHEN GROUPING(extract(year FROM placed_at)) = 1 THEN 'ALL YEARS'
            ELSE extract(year FROM placed_at)::text END AS year,
       CASE WHEN GROUPING(extract(quarter FROM placed_at)) = 1 THEN 'subtotal'
            ELSE 'Q' || extract(quarter FROM placed_at) END  AS quarter,
       sum(grand_total) AS revenue
FROM sales.orders
WHERE status = 'delivered'
GROUP BY ROLLUP (extract(year FROM placed_at), extract(quarter FROM placed_at))
ORDER BY extract(year FROM placed_at) NULLS LAST, extract(quarter FROM placed_at) NULLS LAST;

-- ---------------------------------------------------------------------
-- [Q05.23] Every combination of subtotals
-- Keywords: CUBE
-- Business question: Payments by method and status with all cross-subtotals.
-- ---------------------------------------------------------------------
SELECT COALESCE(method::text, '(all)') AS method, COALESCE(status::text, '(all)') AS status,
       count(*) AS payments, sum(amount) AS amount
FROM sales.payments
WHERE method IN ('upi', 'card')
GROUP BY CUBE (method, status)
ORDER BY method, status;

-- ---------------------------------------------------------------------
-- [Q05.24] Remove duplicate grouping sets
-- Keywords: GROUP BY DISTINCT
-- Business question: ROLLUP(a,b) combined with ROLLUP(a) duplicates sets — dedupe them (PG14+).
-- ---------------------------------------------------------------------
SELECT carrier, status, count(*)
FROM logistics.shipments
GROUP BY DISTINCT ROLLUP (carrier, status), ROLLUP (carrier)
ORDER BY carrier NULLS LAST, status NULLS LAST
LIMIT 12;

-- =====================================================================
-- SECTION: Handy extras
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q05.25] Pick "any" value of a non-grouped column
-- Keywords: any_value()
-- Business question: One example product name per brand, cheaply (PG16+).
-- ---------------------------------------------------------------------
SELECT b.name AS brand, count(*) AS products, any_value(p.name) AS example_product
FROM catalog.products p
JOIN catalog.brands b USING (brand_id)
GROUP BY b.name
ORDER BY products DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q05.26] Aggregating an aggregate needs two levels
-- Keywords: nested aggregation, derived table
-- Business question: Average number of items per order, and average orders per customer.
-- ---------------------------------------------------------------------
SELECT round(avg(items), 2) AS avg_items_per_order
FROM (SELECT order_id, count(*) AS items FROM sales.order_items GROUP BY order_id) per_order;
SELECT round(avg(orders), 2) AS avg_orders_per_buyer, max(orders) AS max_orders
FROM (SELECT user_id, count(*) AS orders FROM sales.orders GROUP BY user_id) per_user;

-- ---------------------------------------------------------------------
-- [Q05.27] Distribution of a count ("histogram of a histogram")
-- Keywords: GROUP BY on an aggregated result
-- Business question: How many customers have 1 order, 2 orders, 3 orders …?
-- ---------------------------------------------------------------------
SELECT orders_placed, count(*) AS customers
FROM (SELECT user_id, count(*) AS orders_placed FROM sales.orders GROUP BY user_id) t
GROUP BY orders_placed
ORDER BY orders_placed
LIMIT 15;

-- ---------------------------------------------------------------------
-- [Q05.28] Weighted average
-- Keywords: sum(x * w) / sum(w)
-- Business question: Average selling price per category weighted by quantity sold.
-- ---------------------------------------------------------------------
SELECT c.name AS category,
       round(sum(oi.unit_price * oi.quantity) / sum(oi.quantity), 2) AS weighted_avg_price,
       round(avg(oi.unit_price), 2) AS simple_avg_price
FROM sales.order_items oi
JOIN catalog.product_variants v USING (variant_id)
JOIN catalog.products p USING (product_id)
JOIN catalog.categories c USING (category_id)
GROUP BY c.name
ORDER BY weighted_avg_price DESC
LIMIT 8;
