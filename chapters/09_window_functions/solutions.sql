-- =====================================================================
--  Chapter 09 · Solutions — window functions
-- =====================================================================

-- [E09.01] Order sequence per user
-- Keywords: row_number() OVER (PARTITION BY … ORDER BY …)
SELECT user_id, order_number, placed_at,
       row_number() OVER (PARTITION BY user_id ORDER BY placed_at) AS order_seq
FROM sales.orders
WHERE user_id = 2
ORDER BY placed_at;

-- [E09.02] Rating vs. product average
-- Keywords: avg() OVER (PARTITION BY …)
SELECT review_id, rating, round(avg(rating) OVER (PARTITION BY product_id), 2) AS product_avg
FROM catalog.reviews
WHERE product_id = 1;

-- [E09.03] Most expensive product per brand, ties kept
-- Keywords: rank(), PARTITION BY
SELECT brand, name, base_price
FROM (SELECT b.name AS brand, p.name, p.base_price,
             rank() OVER (PARTITION BY p.brand_id ORDER BY p.base_price DESC) AS rnk
      FROM catalog.products p JOIN catalog.brands b USING (brand_id)) t
WHERE rnk = 1
ORDER BY base_price DESC;

-- [E09.04] Running average
-- Keywords: avg() OVER (ORDER BY …)
SELECT placed_at, grand_total,
       round(avg(grand_total) OVER (ORDER BY placed_at), 2) AS running_avg
FROM sales.orders
WHERE user_id = 1
ORDER BY placed_at;

-- [E09.05] Daily signups with day-over-day change
-- Keywords: lag(), generate_series(), LEFT JOIN
SELECT d::date AS day, count(u.user_id) AS signups,
       count(u.user_id) - lag(count(u.user_id)) OVER (ORDER BY d) AS change_vs_prev_day
FROM generate_series(current_date - 29, current_date, interval '1 day') d
LEFT JOIN core.users u ON u.created_at::date = d::date
GROUP BY d
ORDER BY d;

-- [E09.06] Seller quartiles by product count
-- Keywords: ntile()
SELECT quartile, count(*) AS sellers, min(products), max(products)
FROM (SELECT seller_id, count(*) AS products, ntile(4) OVER (ORDER BY count(*)) AS quartile
      FROM catalog.products GROUP BY seller_id) t
GROUP BY quartile
ORDER BY quartile;

-- [E09.07] Time to first in-transit scan per carrier
-- Keywords: min() FILTER, GROUP BY, avg() of intervals
SELECT carrier, avg(first_transit - placed_at) AS avg_time_to_transit
FROM (
    SELECT s.carrier, o.placed_at,
           min(e.occurred_at) FILTER (WHERE e.status = 'in_transit') AS first_transit
    FROM logistics.shipments s
    JOIN sales.orders o USING (order_id)
    JOIN logistics.shipment_events e USING (shipment_id)
    GROUP BY s.shipment_id, s.carrier, o.placed_at
) t
WHERE first_transit IS NOT NULL
GROUP BY carrier
ORDER BY avg_time_to_transit;

-- [E09.08] Win-back customers (gap > 180 days)
-- Keywords: lag(), derived table filter
SELECT user_id, gap, placed_at AS returned_on
FROM (SELECT user_id, placed_at,
             placed_at - lag(placed_at) OVER (PARTITION BY user_id ORDER BY placed_at) AS gap
      FROM sales.orders) t
WHERE gap > interval '180 days'
ORDER BY gap DESC
LIMIT 10;

-- [E09.09] 3-month moving average for Laptops
-- Keywords: avg() OVER (ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
SELECT month, revenue,
       round(avg(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3m
FROM (
    SELECT date_trunc('month', o.placed_at)::date AS month, sum(oi.line_total) AS revenue
    FROM sales.order_items oi
    JOIN sales.orders o USING (order_id)
    JOIN catalog.product_variants v USING (variant_id)
    JOIN catalog.products p USING (product_id)
    JOIN catalog.categories c USING (category_id)
    WHERE c.slug = 'laptops'
    GROUP BY 1
) m
ORDER BY month;
