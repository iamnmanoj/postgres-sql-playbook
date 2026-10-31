-- =====================================================================
--  Chapter 09 · Window functions
--  Read-only chapter.
-- =====================================================================

-- =====================================================================
-- SECTION: OVER() basics
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q09.01] An aggregate over the whole result without collapsing rows
-- Keywords: OVER (), sum() OVER, percent of total
-- Business question: Each warehouse's capacity and its share of total capacity.
-- ---------------------------------------------------------------------
SELECT code, capacity,
       sum(capacity) OVER ()                                    AS total_capacity,
       round(100.0 * capacity / sum(capacity) OVER (), 1)       AS pct_of_total
FROM logistics.warehouses
ORDER BY capacity DESC;

-- ---------------------------------------------------------------------
-- [Q09.02] Aggregates per group, still keeping every row
-- Keywords: PARTITION BY
-- Business question: Each product's price vs. its category average.
-- ---------------------------------------------------------------------
SELECT p.name, c.name AS category, p.base_price,
       round(avg(p.base_price) OVER (PARTITION BY p.category_id), 2) AS category_avg,
       round(p.base_price - avg(p.base_price) OVER (PARTITION BY p.category_id), 2) AS diff_from_avg,
       count(*) OVER (PARTITION BY p.category_id) AS products_in_category
FROM catalog.products p
JOIN catalog.categories c USING (category_id)
WHERE c.slug = 'speakers'
ORDER BY p.base_price DESC
LIMIT 8;

-- =====================================================================
-- SECTION: Ranking functions
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q09.03] Number rows, and three ways to rank ties
-- Keywords: row_number(), rank(), dense_rank(), ORDER BY in OVER
-- Business question: Rank products by number of reviews.
-- ---------------------------------------------------------------------
SELECT product_id, review_count,
       row_number() OVER w AS row_num,      -- 1,2,3,4 (ties broken arbitrarily)
       rank()       OVER w AS rnk,          -- 1,2,2,4 (gaps after ties)
       dense_rank() OVER w AS dense_rnk     -- 1,2,2,3 (no gaps)
FROM (SELECT product_id, count(*) AS review_count FROM catalog.reviews GROUP BY product_id) t
WINDOW w AS (ORDER BY review_count DESC)
ORDER BY review_count DESC
LIMIT 12;

-- ---------------------------------------------------------------------
-- [Q09.04] Top-N per group: rank inside each partition, then filter
-- Keywords: row_number() OVER (PARTITION BY … ORDER BY …), derived table filter
-- Business question: The 2 best-selling products (by units) in every leaf category.
-- Note: window functions can't appear in WHERE — filter in an outer query.
-- ---------------------------------------------------------------------
SELECT category, product, units
FROM (
    SELECT c.name AS category, p.name AS product, sum(oi.quantity) AS units,
           row_number() OVER (PARTITION BY c.category_id ORDER BY sum(oi.quantity) DESC) AS rn
    FROM sales.order_items oi
    JOIN catalog.product_variants v USING (variant_id)
    JOIN catalog.products p USING (product_id)
    JOIN catalog.categories c USING (category_id)
    GROUP BY c.category_id, c.name, p.product_id, p.name
) ranked
WHERE rn <= 2
ORDER BY category, units DESC
LIMIT 12;

-- ---------------------------------------------------------------------
-- [Q09.05] Relative position: percentile rank and cumulative distribution
-- Keywords: percent_rank(), cume_dist()
-- Business question: How does each seller's revenue compare to all sellers (percentile)?
-- ---------------------------------------------------------------------
SELECT seller_id, revenue,
       round(percent_rank() OVER (ORDER BY revenue)::numeric, 3) AS pct_rank,   -- 0 … 1
       round(cume_dist()    OVER (ORDER BY revenue)::numeric, 3) AS cume_dist   -- share of rows ≤ me
FROM (SELECT seller_id, sum(line_total) AS revenue FROM sales.order_items GROUP BY seller_id) s
ORDER BY revenue DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q09.06] Split rows into N equal buckets
-- Keywords: ntile()
-- Business question: Customer deciles by lifetime spend; what does each decile spend?
-- ---------------------------------------------------------------------
SELECT decile, count(*) AS customers, min(ltv) AS min_ltv, max(ltv) AS max_ltv, round(sum(ltv) / 1e7, 2) AS ltv_crore
FROM (
    SELECT user_id, sum(grand_total) AS ltv,
           ntile(10) OVER (ORDER BY sum(grand_total) DESC) AS decile
    FROM sales.orders
    WHERE status = 'delivered'
    GROUP BY user_id
) d
GROUP BY decile
ORDER BY decile;

-- ---------------------------------------------------------------------
-- [Q09.07] De-duplicate: keep only the newest row per key
-- Keywords: row_number() for dedup, DELETE pattern
-- Business question: Several payment attempts per order — keep only the latest attempt.
-- ---------------------------------------------------------------------
SELECT order_id, payment_id, status, created_at
FROM (
    SELECT p.*, row_number() OVER (PARTITION BY order_id ORDER BY created_at DESC, payment_id DESC) AS rn
    FROM sales.payments p
    WHERE order_id IN (SELECT order_id FROM sales.payments GROUP BY order_id HAVING count(*) > 1)
) x
WHERE rn = 1
ORDER BY order_id
LIMIT 5;

-- =====================================================================
-- SECTION: Offset functions (looking at other rows)
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q09.08] Previous and next row
-- Keywords: lag(), lead()
-- Business question: For user 1, the gap in days between consecutive orders.
-- ---------------------------------------------------------------------
SELECT order_number, placed_at::date AS order_date,
       lag(placed_at::date)  OVER w AS previous_order,
       placed_at::date - lag(placed_at::date) OVER w AS days_since_previous,
       lead(placed_at::date) OVER w AS next_order
FROM sales.orders
WHERE user_id = 1
WINDOW w AS (ORDER BY placed_at)
ORDER BY placed_at
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q09.09] lag/lead with an offset and a default
-- Keywords: lag(expr, offset, default)
-- Business question: Compare each month's GMV with the same month 12 months earlier (YoY).
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT date_trunc('month', placed_at)::date AS month, sum(grand_total) AS gmv
    FROM sales.orders WHERE status = 'delivered'
    GROUP BY 1
)
SELECT month, gmv,
       lag(gmv, 1)     OVER (ORDER BY month) AS prev_month_gmv,
       round(100 * (gmv / lag(gmv, 1) OVER (ORDER BY month) - 1), 1) AS mom_growth_pct,
       lag(gmv, 12, 0) OVER (ORDER BY month) AS same_month_last_year      -- 0 when there's no such row
FROM monthly
ORDER BY month DESC
LIMIT 6;

-- ---------------------------------------------------------------------
-- [Q09.10] First, last and n-th value in a window — and the default-frame trap
-- Keywords: first_value(), last_value(), nth_value(), ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
-- Business question: Show each of user 1's orders next to their first, second and most recent order date.
-- ---------------------------------------------------------------------
SELECT placed_at::date,
       first_value(placed_at::date) OVER w_default AS first_order,
       last_value(placed_at::date)  OVER w_default AS last_value_WRONG,   -- = current row!
       last_value(placed_at::date)  OVER w_full    AS last_order,
       nth_value(placed_at::date, 2) OVER w_full   AS second_order
FROM sales.orders
WHERE user_id = 1
WINDOW w_default AS (ORDER BY placed_at),
       w_full    AS (ORDER BY placed_at ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
ORDER BY placed_at
LIMIT 5;

-- =====================================================================
-- SECTION: Running and moving aggregates (frames)
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q09.11] Running total
-- Keywords: sum() OVER (ORDER BY), cumulative sum
-- Business question: Cumulative GMV over the days of the current month.
-- ---------------------------------------------------------------------
SELECT placed_at::date AS day, sum(grand_total) AS gmv,
       sum(sum(grand_total)) OVER (ORDER BY placed_at::date) AS cumulative_gmv    -- window over an aggregate
FROM sales.orders
WHERE placed_at >= date_trunc('month', now()) AND status <> 'cancelled'
GROUP BY placed_at::date
ORDER BY day;

-- ---------------------------------------------------------------------
-- [Q09.12] Moving average over the last N rows
-- Keywords: ROWS BETWEEN n PRECEDING AND CURRENT ROW
-- Business question: 7-day moving average of daily orders (last 3 weeks).
-- ---------------------------------------------------------------------
SELECT day, orders,
       round(avg(orders) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS moving_avg_7
FROM (SELECT placed_at::date AS day, count(*) AS orders
      FROM sales.orders WHERE placed_at >= current_date - 27 GROUP BY 1) d
ORDER BY day DESC
LIMIT 21;

-- ---------------------------------------------------------------------
-- [Q09.13] Frames by VALUE distance (not row count)
-- Keywords: RANGE BETWEEN interval PRECEDING AND CURRENT ROW
-- Business question: For each order of user 1, how much did they spend in the 30 days up to that order?
-- Note: RANGE with an interval counts all rows whose ORDER BY value is within the distance — gaps don't matter.
-- ---------------------------------------------------------------------
SELECT placed_at, grand_total,
       sum(grand_total) OVER (ORDER BY placed_at RANGE BETWEEN interval '30 days' PRECEDING AND CURRENT ROW) AS spend_last_30d,
       count(*)         OVER (ORDER BY placed_at RANGE BETWEEN interval '30 days' PRECEDING AND CURRENT ROW) AS orders_last_30d
FROM sales.orders
WHERE user_id = 1
ORDER BY placed_at
LIMIT 10;

-- ---------------------------------------------------------------------
-- [Q09.14] Frames by peer groups
-- Keywords: GROUPS BETWEEN, peers
-- Business question: Rating smoothing: average helpful_count of reviews with this rating and adjacent ratings.
-- ---------------------------------------------------------------------
SELECT DISTINCT rating,
       round(avg(helpful_count) OVER (ORDER BY rating GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING), 3) AS avg_helpful_neighbours
FROM catalog.reviews
ORDER BY rating;

-- ---------------------------------------------------------------------
-- [Q09.15] Exclude rows from the frame
-- Keywords: EXCLUDE CURRENT ROW, EXCLUDE TIES, EXCLUDE GROUP
-- Business question: Compare each laptop's price with the average of OTHER laptops.
-- ---------------------------------------------------------------------
SELECT p.name, p.base_price,
       round(avg(p.base_price) OVER (ORDER BY p.base_price ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                                     EXCLUDE CURRENT ROW), 2) AS avg_of_others
FROM catalog.products p
JOIN catalog.categories c USING (category_id)
WHERE c.slug = 'laptops'
ORDER BY p.base_price DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q09.16] Name and reuse window definitions
-- Keywords: WINDOW clause, window inheritance
-- Business question: Per seller per month: revenue, running yearly total and the month rank.
-- ---------------------------------------------------------------------
SELECT seller_id, month, revenue,
       sum(revenue) OVER (seller_year ORDER BY month) AS ytd_revenue,       -- extends the named window
       rank() OVER (seller_year ORDER BY revenue DESC) AS best_month_rank
FROM (
    SELECT oi.seller_id, date_trunc('month', o.placed_at)::date AS month, sum(oi.line_total) AS revenue
    FROM sales.order_items oi JOIN sales.orders o USING (order_id)
    WHERE oi.seller_id = 3 AND o.status = 'delivered'
    GROUP BY 1, 2
) m
WINDOW seller_year AS (PARTITION BY seller_id, date_trunc('year', month))
ORDER BY month
LIMIT 12;

-- ---------------------------------------------------------------------
-- [Q09.17] Conditional window aggregates
-- Keywords: FILTER with OVER
-- Business question: For each day: orders, and running count of cancelled orders this month.
-- ---------------------------------------------------------------------
SELECT placed_at::date AS day,
       count(*) AS orders,
       sum(count(*) FILTER (WHERE status = 'cancelled')) OVER (ORDER BY placed_at::date) AS running_cancelled
FROM sales.orders
WHERE placed_at >= date_trunc('month', now()) - interval '1 month'
  AND placed_at <  date_trunc('month', now())
GROUP BY 1
ORDER BY 1
LIMIT 10;

-- =====================================================================
-- SECTION: Classic analytics patterns
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q09.18] Gaps and islands: streaks of consecutive days
-- Keywords: row_number() difference trick, islands
-- Business question: The longest streaks of consecutive days on which our top 3 customers (1, 2, 4) placed orders.
-- ---------------------------------------------------------------------
WITH days AS (
    SELECT DISTINCT placed_at::date AS d FROM sales.orders WHERE user_id IN (1, 2, 4)
), grouped AS (
    SELECT d, d - (row_number() OVER (ORDER BY d))::int AS island   -- constant within a streak
    FROM days
)
SELECT min(d) AS streak_start, max(d) AS streak_end, count(*) AS days
FROM grouped
GROUP BY island
ORDER BY days DESC, streak_start
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q09.19] Sessionization: start a new session after 30 minutes of inactivity
-- Keywords: lag(), running sum of a flag
-- Business question: Rebuild browsing sessions for user 77 from raw events, ignoring session_id.
-- ---------------------------------------------------------------------
WITH e AS (
    SELECT occurred_at, event_type,
           CASE WHEN occurred_at - lag(occurred_at) OVER (ORDER BY occurred_at) <= interval '30 minutes'
                THEN 0 ELSE 1 END AS new_session
    FROM analytics.events
    WHERE user_id = 77
)
SELECT sum(new_session) OVER (ORDER BY occurred_at) AS session_no, occurred_at, event_type
FROM e
ORDER BY occurred_at
LIMIT 12;

-- ---------------------------------------------------------------------
-- [Q09.20] Cohort retention matrix
-- Keywords: first_value() / min() OVER, cohort analysis
-- Business question: Of users whose first order was in month X, what % ordered again N months later?
-- ---------------------------------------------------------------------
WITH orders_m AS (
    SELECT user_id, date_trunc('month', placed_at)::date AS month
    FROM sales.orders
    WHERE status <> 'cancelled'
    GROUP BY 1, 2
), with_cohort AS (
    SELECT user_id, month, min(month) OVER (PARTITION BY user_id) AS cohort
    FROM orders_m
), offsets AS (
    SELECT cohort,
           (extract(year FROM age(month, cohort)) * 12 + extract(month FROM age(month, cohort)))::int AS month_no,
           count(DISTINCT user_id) AS users
    FROM with_cohort
    GROUP BY 1, 2
)
SELECT cohort,
       max(users) FILTER (WHERE month_no = 0) AS cohort_size,
       round(100.0 * max(users) FILTER (WHERE month_no = 1) / max(users) FILTER (WHERE month_no = 0), 1) AS m1_pct,
       round(100.0 * max(users) FILTER (WHERE month_no = 2) / max(users) FILTER (WHERE month_no = 0), 1) AS m2_pct,
       round(100.0 * max(users) FILTER (WHERE month_no = 3) / max(users) FILTER (WHERE month_no = 0), 1) AS m3_pct
FROM offsets
GROUP BY cohort
ORDER BY cohort DESC
OFFSET 3 LIMIT 6;

-- ---------------------------------------------------------------------
-- [Q09.21] Pareto / ABC analysis with a running share
-- Keywords: running sum / total sum, CASE on window result
-- Business question: Which products make up the first 80% of revenue (class A)?
-- ---------------------------------------------------------------------
SELECT abc_class, count(*) AS products, round(sum(revenue) / 1e7, 2) AS revenue_crore
FROM (
    SELECT product_id, revenue,
           CASE WHEN sum(revenue) OVER (ORDER BY revenue DESC) <= 0.8 * sum(revenue) OVER () THEN 'A'
                WHEN sum(revenue) OVER (ORDER BY revenue DESC) <= 0.95 * sum(revenue) OVER () THEN 'B'
                ELSE 'C' END AS abc_class
    FROM (SELECT v.product_id, sum(oi.line_total) AS revenue
          FROM sales.order_items oi JOIN catalog.product_variants v USING (variant_id)
          GROUP BY v.product_id) r
) x
GROUP BY abc_class
ORDER BY abc_class;

-- ---------------------------------------------------------------------
-- [Q09.22] Durations between consecutive events of the same entity
-- Keywords: lag() OVER (PARTITION BY …), timestamp difference
-- Business question: Shipment timeline: how long did a parcel spend in each status?
-- ---------------------------------------------------------------------
SELECT shipment_id, status, location, occurred_at,
       occurred_at - lag(occurred_at) OVER (PARTITION BY shipment_id ORDER BY occurred_at) AS time_in_previous_status
FROM logistics.shipment_events
WHERE shipment_id = (SELECT min(shipment_id) FROM logistics.shipments WHERE status = 'delivered')
ORDER BY occurred_at;
