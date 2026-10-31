-- =====================================================================
--  Chapter 04 · Built-in functions & casting
--  Read-only chapter.
-- =====================================================================

-- =====================================================================
-- SECTION: String functions
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q04.01] Length and letter case
-- Keywords: length(), char_length(), octet_length(), upper(), lower(), initcap()
-- Business question: Normalise messy customer names (e.g. 'aarav  SHARMA').
-- ---------------------------------------------------------------------
SELECT full_name,
       length(full_name)       AS chars,
       octet_length('₹')       AS bytes_of_rupee_sign,   -- UTF-8 multi-byte
       upper(full_name)        AS shouting,
       lower(full_name)        AS whisper,
       initcap(full_name)      AS proper_case
FROM core.users
WHERE full_name ~ '  '
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q04.02] Trimming whitespace and characters
-- Keywords: trim(), btrim(), ltrim(), rtrim(), regexp_replace()
-- Business question: Clean user input: '  ##SAVE20##  ' → 'SAVE20', and collapse inner spaces.
-- ---------------------------------------------------------------------
SELECT trim('  ##SAVE20##  ')                        AS trim_spaces,
       btrim(trim('  ##SAVE20##  '), '#')            AS btrim_hash,
       ltrim('000123', '0')                          AS ltrim_zeros,
       rtrim('Order!!!', '!')                        AS rtrim_bang,
       regexp_replace('aarav    SHARMA', '\s+', ' ', 'g') AS collapse_spaces;

-- ---------------------------------------------------------------------
-- [Q04.03] Extract parts of strings
-- Keywords: substring(), substr(), left(), right(), split_part()
-- Business question: Split emails into user part and domain; get the date part of order numbers.
-- ---------------------------------------------------------------------
SELECT email,
       split_part(email::text, '@', 1)  AS local_part,
       split_part(email::text, '@', 2)  AS domain,
       left(email::text, 3)             AS first3,
       right(email::text, 4)            AS last4
FROM core.users LIMIT 3;
SELECT order_number,
       substring(order_number FROM 4 FOR 8) AS yyyymmdd_sql_standard,
       substr(order_number, 4, 8)           AS yyyymmdd_short_form
FROM sales.orders LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q04.04] Find text inside text
-- Keywords: position(), strpos()
-- Business question: Where does the word "and" appear in product descriptions?
-- ---------------------------------------------------------------------
SELECT left(description, 60) AS description,
       position(' and ' IN description) AS pos_standard,
       strpos(description, ' and ')     AS pos_postgres
FROM catalog.products
WHERE description IS NOT NULL
LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q04.05] Replace text
-- Keywords: replace(), translate()
-- Business question: Make URL-friendly slugs; mask digits in phone numbers.
-- ---------------------------------------------------------------------
SELECT name,
       replace(lower(name), ' ', '-')                  AS slug_like,
       translate('+919876543210', '0123456789', '**********') AS masked_all_digits
FROM catalog.products LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q04.06] Pad and repeat
-- Keywords: lpad(), rpad(), repeat(), reverse()
-- Business question: Mask card numbers as "XXXX-XXXX-XXXX-1234".
-- ---------------------------------------------------------------------
SELECT payment_id,
       gateway_response->'card'->>'last4' AS last4,
       repeat('XXXX-', 3) || (gateway_response->'card'->>'last4') AS masked_card,
       lpad(payment_id::text, 10, '0') AS padded_id,
       rpad('Total', 12, '.') || ' ₹' || amount AS receipt_line,
       reverse('ShopSphere') AS mirrored
FROM sales.payments
WHERE method = 'card' AND status = 'captured'
LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q04.07] NULL-friendly concatenation
-- Keywords: concat(), concat_ws()
-- Business question: Full address with optional line2 (|| would return NULL).
-- ---------------------------------------------------------------------
SELECT concat(line1, ', ', line2, ', ', city)       AS concat_ignores_null,
       concat_ws(', ', line1, line2, city, postal_code) AS concat_ws_skips_null_and_separator
FROM core.addresses
WHERE line2 IS NULL
LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q04.08] printf-style formatting and safe quoting
-- Keywords: format(), quote_ident(), quote_literal()
-- Business question: Build a notification message; build safe dynamic SQL text.
-- ---------------------------------------------------------------------
SELECT format('Hi %s, your order %s of ₹%s has shipped!', split_part(u.full_name, ' ', 1), o.order_number, o.grand_total) AS message,
       format('%-10s|%10s|', 'left', 'right') AS aligned,
       quote_ident('Order Items') AS quoted_identifier,
       quote_literal('Rohan''s store') AS quoted_literal
FROM sales.orders o JOIN core.users u USING (user_id)
LIMIT 2;

-- ---------------------------------------------------------------------
-- [Q04.09] Strings ⇄ arrays/rows
-- Keywords: string_to_array(), string_to_table(), array_to_string()
-- Business question: A seller uploaded tags as "gift,eco-friendly,sale".
-- ---------------------------------------------------------------------
SELECT string_to_array('gift,eco-friendly,sale', ',')  AS as_array,
       array_to_string(ARRAY['red', 'blue'], ' / ')     AS as_text;
SELECT tag FROM string_to_table('gift,eco-friendly,sale', ',') AS tag;   -- PG14+: one row per piece

-- ---------------------------------------------------------------------
-- [Q04.10] Regular-expression functions
-- Keywords: regexp_matches(), regexp_count(), regexp_substr(), regexp_like()
-- Business question: Pull model numbers out of product names; count digits in phone numbers.
-- ---------------------------------------------------------------------
SELECT name,
       regexp_substr(name, '[0-9]+')                 AS first_number,       -- PG15+
       regexp_count(name, '[aeiou]', 1, 'i')         AS vowels,             -- PG15+
       regexp_like(name, '^(Voltix|Auralux)')        AS is_audio_brand,     -- PG15+
       regexp_matches(name, '(Pro|Max|Ultra|Lite|Neo|Air|Plus|Mini) ([0-9]+)') AS model_parts
FROM catalog.products
WHERE name ~ '(Pro|Max|Ultra|Lite|Neo|Air|Plus|Mini) [0-9]+'
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q04.11] Hashing and encoding
-- Keywords: md5(), sha256(), encode(), decode(), convert_to()
-- Business question: Create a stable anonymous id for analytics; base64-encode a payload.
-- ---------------------------------------------------------------------
SELECT md5(email::text)                                        AS md5_hex,
       encode(sha256(convert_to(email::text, 'UTF8')), 'hex')  AS sha256_hex,
       encode(convert_to('order:42', 'UTF8'), 'base64')        AS base64,
       convert_from(decode('b3JkZXI6NDI=', 'base64'), 'UTF8')  AS decoded
FROM core.users LIMIT 2;

-- =====================================================================
-- SECTION: Numeric functions
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q04.12] Rounding family
-- Keywords: round(), trunc(), ceil(), floor()
-- Business question: Show prices rounded to rupees, to hundreds, and boxes needed for weights.
-- ---------------------------------------------------------------------
SELECT base_price,
       round(base_price)        AS nearest_rupee,
       round(base_price, -2)    AS nearest_hundred,
       trunc(base_price, 1)     AS truncated_1dp,
       ceil(weight_grams / 1000.0)  AS kg_boxes_needed,
       floor(base_price / 1000) AS thousands
FROM catalog.products LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q04.13] The integer-division trap
-- Keywords: /, div(), %, mod(), ::numeric
-- Business question: What % of orders were cancelled? (Watch the first column!)
-- ---------------------------------------------------------------------
SELECT 7 / 2               AS int_division,       -- 3, not 3.5
       7 / 2.0             AS numeric_division,
       div(7, 2)           AS div_func,
       7 % 2               AS remainder,
       mod(-7, 2)          AS mod_negative;
SELECT count(*) FILTER (WHERE status = 'cancelled') * 100 / count(*)          AS wrong_pct,
       round(count(*) FILTER (WHERE status = 'cancelled') * 100.0 / count(*), 2) AS right_pct
FROM sales.orders;

-- ---------------------------------------------------------------------
-- [Q04.14] Powers, roots, absolute values, signs
-- Keywords: abs(), power(), sqrt(), cbrt(), exp(), ln(), log(), sign()
-- Business question: Compound growth: if GMV grows 4% a month, what's the yearly multiplier?
-- ---------------------------------------------------------------------
SELECT round(power(1.04, 12)::numeric, 4) AS yearly_multiplier,
       sqrt(144) AS sqrt, cbrt(27) AS cbrt, round(exp(1)::numeric, 5) AS e,
       round(ln(10)::numeric, 4) AS ln10, log(1000) AS log10,
       abs(-250) AS abs_val, sign(-250) AS sign_val;

-- ---------------------------------------------------------------------
-- [Q04.15] Bucket values into equal-width bins
-- Keywords: width_bucket()
-- Business question: Histogram of product prices up to ₹50,000 in 5 buckets.
-- ---------------------------------------------------------------------
SELECT width_bucket(base_price, 0, 50000, 5) AS bucket, count(*) AS products,
       min(base_price) AS from_price, max(base_price) AS to_price
FROM catalog.products
GROUP BY bucket
ORDER BY bucket;

-- =====================================================================
-- SECTION: Date & time functions
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q04.16] "What time is it?" — and why there are several answers
-- Keywords: now(), current_timestamp, current_date, current_time, localtimestamp, clock_timestamp(), statement_timestamp(), transaction_timestamp()
-- Note: now() is frozen for the whole transaction; clock_timestamp() changes every call.
-- ---------------------------------------------------------------------
SELECT now(), current_timestamp, transaction_timestamp(), statement_timestamp(),
       clock_timestamp(), current_date, current_time, localtimestamp;

-- ---------------------------------------------------------------------
-- [Q04.17] Truncate timestamps to a unit
-- Keywords: date_trunc()
-- Business question: Orders per week for the last 6 weeks.
-- ---------------------------------------------------------------------
SELECT date_trunc('week', placed_at)::date AS week_start, count(*) AS orders
FROM sales.orders
WHERE placed_at >= date_trunc('week', now()) - interval '5 weeks'
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- [Q04.18] Pull fields out of dates
-- Keywords: extract(), date_part(), dow, isodow, epoch, quarter
-- Business question: Which weekday do customers order on most?
-- ---------------------------------------------------------------------
SELECT extract(isodow FROM placed_at) AS iso_weekday,        -- 1 = Monday … 7 = Sunday
       to_char(placed_at, 'Dy')         AS day_name,
       count(*) AS orders
FROM sales.orders
GROUP BY 1, 2
ORDER BY 1;
SELECT extract(quarter FROM now()) AS quarter, date_part('year', now()) AS year,
       extract(epoch FROM now())::bigint AS unix_seconds;

-- ---------------------------------------------------------------------
-- [Q04.19] Interval arithmetic and age
-- Keywords: interval, age(), timestamp - timestamp, date - date, date + integer
-- Business question: How old is each customer and how long have they been with us?
-- ---------------------------------------------------------------------
SELECT full_name,
       age(date_of_birth)                    AS age_interval,
       extract(year FROM age(date_of_birth)) AS age_years,
       now() - created_at                    AS member_for,
       current_date - created_at::date       AS member_days,
       current_date + 7                      AS one_week_from_today
FROM core.users
WHERE date_of_birth IS NOT NULL
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q04.20] Build dates and intervals from parts
-- Keywords: make_date(), make_timestamptz(), make_interval()
-- Business question: The Diwali sale starts on 1 Nov this year at 00:00 IST and lasts 5 days 12 hours.
-- ---------------------------------------------------------------------
SELECT make_date(extract(year FROM now())::int, 11, 1)                          AS sale_date,
       make_timestamptz(extract(year FROM now())::int, 11, 1, 0, 0, 0, 'Asia/Kolkata') AS sale_starts,
       make_interval(days => 5, hours => 12)                                  AS sale_length;

-- ---------------------------------------------------------------------
-- [Q04.21] Format dates and numbers as text
-- Keywords: to_char()
-- Business question: Invoice-style dates and Indian-format amounts.
-- ---------------------------------------------------------------------
SELECT order_number,
       to_char(placed_at, 'DD Mon YYYY, HH12:MI AM')  AS pretty_date,
       to_char(placed_at, 'FMDay, FMDDth FMMonth')     AS long_date,
       to_char(grand_total, 'FM99,99,99,990.00')       AS amount_text
FROM sales.orders
ORDER BY grand_total DESC
LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q04.22] Parse text into dates, timestamps and numbers
-- Keywords: to_date(), to_timestamp(), to_number()
-- Business question: A CSV from a courier has '31/12/2025', '2025-12-31 18:45' and '₹1,234.50'.
-- ---------------------------------------------------------------------
SELECT to_date('31/12/2025', 'DD/MM/YYYY')                     AS parsed_date,
       to_timestamp('2025-12-31 18:45', 'YYYY-MM-DD HH24:MI')  AS parsed_ts,
       to_timestamp(1767225600)                                 AS from_unix_epoch,
       to_number('₹1,234.50', 'L9G999D99')                      AS parsed_amount;

-- ---------------------------------------------------------------------
-- [Q04.23] Time zones
-- Keywords: AT TIME ZONE, timezone(), SET TIME ZONE
-- Business question: Show order times in India and New York time.
-- ---------------------------------------------------------------------
SELECT placed_at                                AS stored_utc,
       placed_at AT TIME ZONE 'Asia/Kolkata'    AS ist_wall_clock,
       timezone('America/New_York', placed_at)  AS new_york_wall_clock
FROM sales.orders LIMIT 3;
SET TIME ZONE 'Asia/Kolkata';
SELECT placed_at AS shown_in_session_zone FROM sales.orders LIMIT 1;
RESET TIME ZONE;

-- ---------------------------------------------------------------------
-- [Q04.24] Bin timestamps into arbitrary-width buckets
-- Keywords: date_bin()
-- Business question: Click-stream volume per 15-minute slot during the last hour (PG14+).
-- ---------------------------------------------------------------------
SELECT date_bin('15 minutes', occurred_at, TIMESTAMPTZ '2000-01-01') AS slot, count(*) AS events
FROM analytics.events
WHERE occurred_at >= now() - interval '1 day'
GROUP BY slot
ORDER BY slot DESC
LIMIT 4;

-- ---------------------------------------------------------------------
-- [Q04.25] Normalise intervals; test overlap of periods
-- Keywords: justify_days(), justify_hours(), justify_interval(), OVERLAPS, isfinite()
-- Business question: Does a planned maintenance window overlap the festive coupon window?
-- ---------------------------------------------------------------------
SELECT justify_days(interval '65 days')     AS days_to_months,
       justify_hours(interval '50 hours')   AS hours_to_days,
       justify_interval(interval '1 month -1 hour') AS normalised,
       (now(), now() + interval '2 hours') OVERLAPS (now() + interval '1 hour', interval '1 day') AS windows_overlap,
       isfinite('infinity'::timestamptz)   AS infinity_is_finite;

-- =====================================================================
-- SECTION: Casting & type inspection
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q04.26] Two cast syntaxes and inspecting types
-- Keywords: CAST(), ::, pg_typeof()
-- ---------------------------------------------------------------------
SELECT CAST('42' AS integer)      AS standard_cast,
       '42'::integer + 1          AS postgres_cast,
       '2025-03-01'::date + 1     AS date_math,
       'true'::boolean            AS bool_from_text,
       pg_typeof(1.5)             AS type_of_literal,
       pg_typeof(now())           AS type_of_now,
       pg_typeof(grand_total)     AS type_of_column
FROM sales.orders LIMIT 1;

-- ---------------------------------------------------------------------
-- [Q04.27] Casting enums, JSON values and text safely
-- Keywords: ::text, ::jsonb, pg_input_is_valid()
-- Business question: Validate user-supplied input before casting it (PG16+).
-- ---------------------------------------------------------------------
SELECT status::text || '!'                         AS enum_as_text,
       '{"a":1}'::jsonb ->> 'a'                     AS json_value,
       pg_input_is_valid('12.5', 'numeric')        AS valid_number,
       pg_input_is_valid('12,5', 'numeric')        AS invalid_number,
       pg_input_is_valid('2025-02-30', 'date')     AS invalid_date
FROM sales.orders LIMIT 1;

-- =====================================================================
-- SECTION: UUID & misc helpers
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q04.28] UUIDs and handy system functions
-- Keywords: gen_random_uuid(), current_database(), pg_backend_pid(), num_nonnulls(), num_nulls()
-- Business question: How complete are user profiles (count missing optional fields)?
-- ---------------------------------------------------------------------
SELECT gen_random_uuid() AS new_uuid, current_database(), pg_backend_pid();
SELECT user_id,
       num_nulls(phone, date_of_birth, last_login_at, referred_by)    AS missing_fields,
       num_nonnulls(phone, date_of_birth, last_login_at, referred_by) AS filled_fields
FROM core.users
ORDER BY missing_fields DESC
LIMIT 5;
