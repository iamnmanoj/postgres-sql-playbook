-- =====================================================================
--  Chapter 04 · Solutions — built-in functions & casting
-- =====================================================================

-- [E04.01] Store name lengths
-- Keywords: upper(), length(), ORDER BY
SELECT store_name, upper(store_name) AS upper_name, length(store_name) AS name_length
FROM core.sellers
ORDER BY name_length DESC, store_name
LIMIT 10;

-- [E04.02] Years open
-- Keywords: age(), extract()
SELECT code, opened_on, extract(year FROM age(current_date, opened_on))::int AS years_open
FROM logistics.warehouses
ORDER BY years_open DESC;

-- [E04.03] Users per email domain
-- Keywords: split_part(), GROUP BY, count()
SELECT split_part(email::text, '@', 2) AS domain, count(*) AS users
FROM core.users
GROUP BY domain
ORDER BY users DESC;

-- [E04.04] Formatted order message in IST
-- Keywords: format(), to_char(), AT TIME ZONE
SELECT format('%s placed on %s IST for ₹%s',
              order_number,
              to_char(placed_at AT TIME ZONE 'Asia/Kolkata', 'Dy DD Mon YYYY "at" HH24:MI'),
              to_char(grand_total, 'FM99,99,99,990.00')) AS message
FROM sales.orders
ORDER BY placed_at DESC
LIMIT 5;

-- [E04.05] Last 6 complete months
-- Keywords: date_trunc(), to_char(), interval
SELECT to_char(date_trunc('month', placed_at), 'Mon YYYY') AS month, count(*) AS orders
FROM sales.orders
WHERE placed_at >= date_trunc('month', now()) - interval '6 months'
  AND placed_at <  date_trunc('month', now())
GROUP BY date_trunc('month', placed_at)
ORDER BY date_trunc('month', placed_at);

-- [E04.06] Mask phone numbers
-- Keywords: left(), right(), repeat(), length()
SELECT user_id, phone,
       left(phone, 3) || repeat('*', length(phone) - 6) || right(phone, 3) AS masked
FROM core.users
WHERE phone IS NOT NULL
LIMIT 5;

-- [E04.07] Average transit hours per carrier
-- Keywords: extract(epoch …), avg(), round()
SELECT carrier,
       round(avg(extract(epoch FROM delivered_at - shipped_at) / 3600)::numeric, 1) AS avg_transit_hours
FROM logistics.shipments
WHERE status = 'delivered'
GROUP BY carrier
ORDER BY avg_transit_hours;

-- [E04.08] Human-friendly weights
-- Keywords: CASE, round(), ::text
SELECT name, weight_grams,
       CASE WHEN weight_grams >= 1000 THEN round(weight_grams / 1000.0, 2) || ' kg'
            ELSE weight_grams || ' g' END AS weight_label
FROM catalog.products
LIMIT 10;

-- [E04.09] Validate without errors
-- Keywords: pg_input_is_valid(), VALUES
SELECT v AS candidate,
       v ~ '^[1-9][0-9]{5}$'          AS valid_pincode,
       pg_input_is_valid(v, 'date')  AS valid_date
FROM (VALUES ('560001'), ('5600A1'), ('2025-02-28'), ('2025-02-30')) AS t(v);
