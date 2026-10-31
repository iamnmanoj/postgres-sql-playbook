-- =====================================================================
--  Chapter 12 · JSONB & arrays
--  Changes to app tables are rolled back.
-- =====================================================================

-- =====================================================================
-- SECTION: Reading JSONB
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q12.01] Get a value as JSON or as text
-- Keywords: ->, ->>
-- Business question: Show each order's sales channel and device.
-- ---------------------------------------------------------------------
SELECT order_number,
       metadata -> 'channel'   AS channel_json,      -- jsonb: "app" (with quotes)
       metadata ->> 'channel'  AS channel_text,      -- text:  app
       metadata ->> 'device'   AS device
FROM sales.orders
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q12.02] Navigate nested objects and arrays
-- Keywords: -> chain, #>, #>>, array index ->0
-- Business question: Marketing source of orders, card network of payments, first connectivity option.
-- ---------------------------------------------------------------------
SELECT order_number,
       metadata -> 'utm' ->> 'source'   AS utm_source,     -- chained
       metadata #>> '{utm,campaign}'    AS utm_campaign    -- path as text
FROM sales.orders
WHERE metadata ? 'utm'
LIMIT 3;
SELECT name, attributes -> 'connectivity' -> 0 AS first_option, attributes #> '{specs}' AS specs_json
FROM catalog.products
WHERE attributes ? 'connectivity'
LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q12.03] Cast extracted values to proper types
-- Keywords: (->>)::int, ::numeric, ::boolean
-- Business question: Electronics with at least 16 GB RAM and a warranty over 12 months.
-- ---------------------------------------------------------------------
SELECT name, (attributes #>> '{specs,ram_gb}')::int AS ram_gb, (attributes ->> 'warranty_months')::int AS warranty
FROM catalog.products
WHERE (attributes #>> '{specs,ram_gb}')::int >= 16
  AND (attributes ->> 'warranty_months')::int > 12
LIMIT 5;

-- =====================================================================
-- SECTION: Querying JSONB with operators
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q12.04] Containment: does the document contain this sub-document?
-- Keywords: @>, <@
-- Business question: Orders placed from the iOS app with gift wrap.
-- Note: @> can use a GIN index (ch14), unlike ->> = comparisons.
-- ---------------------------------------------------------------------
SELECT count(*) AS ios_app_gift_orders
FROM sales.orders
WHERE metadata @> '{"channel": "app", "device": "ios", "gift_wrap": true}';
SELECT '{"channel": "app"}'::jsonb <@ metadata AS is_contained FROM sales.orders LIMIT 1;

-- ---------------------------------------------------------------------
-- [Q12.05] Key existence
-- Keywords: ?, ?|, ?&
-- Business question: Users with a theme preference; products having any/all of some spec keys.
-- ---------------------------------------------------------------------
SELECT count(*) FILTER (WHERE preferences ? 'theme')                              AS has_theme,
       count(*) FILTER (WHERE preferences -> 'notifications' ?| ARRAY['sms', 'whatsapp']) AS has_sms_or_whatsapp_key,
       count(*) FILTER (WHERE preferences ?& ARRAY['language', 'newsletter'])     AS has_both
FROM core.users;

-- ---------------------------------------------------------------------
-- [Q12.06] Inspect types and structure
-- Keywords: jsonb_typeof(), jsonb_object_keys(), jsonb_array_length(), jsonb_pretty()
-- Business question: Which attribute keys exist across the catalog and how often?
-- ---------------------------------------------------------------------
SELECT k AS attribute_key, count(*) AS products, any_value(jsonb_typeof(attributes -> k)) AS json_type
FROM catalog.products, jsonb_object_keys(attributes) AS k
GROUP BY k
ORDER BY products DESC;
SELECT jsonb_array_length(attributes -> 'connectivity') AS options, jsonb_pretty(attributes) AS pretty
FROM catalog.products WHERE attributes ? 'connectivity' LIMIT 1;

-- =====================================================================
-- SECTION: Expanding JSONB into rows
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q12.07] Object → key/value rows
-- Keywords: jsonb_each(), jsonb_each_text()
-- Business question: Show user 1's notification settings as rows.
-- ---------------------------------------------------------------------
SELECT key AS channel, value AS enabled_json
FROM core.users, jsonb_each(preferences -> 'notifications')
WHERE user_id = 1;
SELECT key, value FROM core.users, jsonb_each_text(preferences) WHERE user_id = 1;

-- ---------------------------------------------------------------------
-- [Q12.08] Array → rows
-- Keywords: jsonb_array_elements(), jsonb_array_elements_text()
-- Business question: How many products support each connectivity option?
-- ---------------------------------------------------------------------
SELECT opt, count(*) AS products
FROM catalog.products, jsonb_array_elements_text(attributes -> 'connectivity') AS opt
GROUP BY opt
ORDER BY products DESC;

-- ---------------------------------------------------------------------
-- [Q12.09] JSON → typed columns (a record)
-- Keywords: jsonb_to_record(), jsonb_populate_record()
-- Business question: Turn book attributes into proper columns.
-- ---------------------------------------------------------------------
SELECT p.name, b.*
FROM catalog.products p
CROSS JOIN LATERAL jsonb_to_record(p.attributes) AS b(author text, pages int, language text, format text, isbn text)
WHERE p.attributes ? 'isbn'
LIMIT 5;
CREATE TEMP TABLE IF NOT EXISTS book_row (author text, pages int, language text);
SELECT (jsonb_populate_record(NULL::book_row, attributes)).*
FROM catalog.products WHERE attributes ? 'isbn' LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q12.10] An array of objects → a table
-- Keywords: jsonb_to_recordset()
-- Business question: A partner API sends order lines as a JSON array; read it like a table.
-- ---------------------------------------------------------------------
SELECT *
FROM jsonb_to_recordset('[{"sku":"SKU-000001-V1","qty":2,"price":2412.99},
                          {"sku":"SKU-000004-V1","qty":1,"price":176626.99}]')
     AS line(sku text, qty int, price numeric);

-- =====================================================================
-- SECTION: Building & modifying JSONB
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q12.11] Build JSON from columns and rows
-- Keywords: jsonb_build_object(), jsonb_build_array(), to_jsonb(), row_to_json(), json_build_object()
-- Business question: Produce an API payload for an order (header + nested address).
-- ---------------------------------------------------------------------
SELECT jsonb_build_object(
           'order', o.order_number,
           'total', o.grand_total,
           'status', o.status,
           'ship_to', jsonb_build_object('city', a.city, 'pin', a.postal_code),
           'flags', jsonb_build_array(o.metadata ? 'gift_wrap', o.coupon_id IS NOT NULL)
       ) AS api_payload
FROM sales.orders o JOIN core.addresses a ON a.address_id = o.shipping_address_id
WHERE o.order_id = 7;
SELECT to_jsonb(w) AS warehouse_as_jsonb, row_to_json(w) AS warehouse_as_json
FROM logistics.warehouses w WHERE warehouse_id = 1;

-- ---------------------------------------------------------------------
-- [Q12.12] Merge, remove keys, remove paths, drop nulls
-- Keywords: || (merge), - key, - array of keys, #- path, jsonb_strip_nulls()
-- ---------------------------------------------------------------------
SELECT preferences || '{"theme": "light", "currency": "INR"}'   AS merged,      -- right side wins
       preferences - 'newsletter'                               AS without_key,
       preferences - ARRAY['language', 'theme']                 AS without_keys,
       preferences #- '{notifications,sms}'                     AS without_nested,
       jsonb_strip_nulls('{"a": 1, "b": null}')                 AS stripped
FROM core.users WHERE user_id = 3;

-- ---------------------------------------------------------------------
-- [Q12.13] Set or insert a value deep inside a document
-- Keywords: jsonb_set(), jsonb_insert(), create_if_missing
-- Business question: Enable WhatsApp notifications for user 3; add 'nfc' as first connectivity option.
-- ---------------------------------------------------------------------
BEGIN;
UPDATE core.users
SET preferences = jsonb_set(preferences, '{notifications,whatsapp}', 'true', true)   -- create_if_missing
WHERE user_id = 3
RETURNING preferences -> 'notifications' AS notifications;
SELECT jsonb_insert(attributes -> 'connectivity', '{0}', '"nfc"') AS with_nfc_first,
       jsonb_insert(attributes -> 'connectivity', '{0}', '"nfc"', true) AS with_nfc_after_first
FROM catalog.products WHERE attributes ? 'connectivity' LIMIT 1;
ROLLBACK;

-- =====================================================================
-- SECTION: SQL/JSON path language
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q12.14] Path predicates
-- Keywords: @?, @@, jsonpath, $, ?(@ …)
-- Business question: Failed payments whose error is retryable; electronics with battery ≥ 5000 mAh.
-- ---------------------------------------------------------------------
SELECT count(*) AS retryable_failures
FROM sales.payments
WHERE gateway_response @? '$ ? (@.retryable == true)';
SELECT count(*) AS big_battery
FROM catalog.products
WHERE attributes @@ '$.specs.battery_mah >= 5000';

-- ---------------------------------------------------------------------
-- [Q12.15] Extract with paths, using variables
-- Keywords: jsonb_path_query(), jsonb_path_query_array(), jsonb_path_query_first(), jsonb_path_exists(), vars
-- Business question: For card payments, extract the network; find payments above a threshold passed as a variable.
-- ---------------------------------------------------------------------
SELECT payment_id,
       jsonb_path_query_first(gateway_response, '$.card.network') AS network,
       jsonb_path_query_array(gateway_response, '$.*')            AS top_level_values
FROM sales.payments WHERE method = 'card' AND status = 'captured' LIMIT 3;
SELECT jsonb_path_query(attributes, '$.connectivity[*] ? (@ starts with "b")') AS starts_with_b
FROM catalog.products WHERE attributes ? 'connectivity' LIMIT 3;
SELECT count(*) AS orders_with_campaign_over_8
FROM sales.orders
WHERE jsonb_path_exists(metadata, '$.utm.campaign ? (@ like_regex "cmp_(9|1[01])")');
SELECT count(*) AS products_with_ram_over_var
FROM catalog.products
WHERE jsonb_path_exists(attributes, '$.specs.ram_gb ? (@ > $min)', '{"min": 8}');

-- =====================================================================
-- SECTION: SQL/JSON standard functions (PG16/PG17)
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q12.16] Validate and construct JSON the standard way
-- Keywords: IS JSON, IS JSON OBJECT, JSON_OBJECT(), JSON_ARRAYAGG()   (PG16+)
-- Business question: Validate a raw webhook body; build a JSON array of warehouse codes.
-- ---------------------------------------------------------------------
SELECT '{"ok": true}' IS JSON          AS valid_json,
       '[1, 2]'       IS JSON OBJECT   AS is_object,
       '{bad json'    IS JSON          AS invalid_json,
       JSON_OBJECT('code': 'BLR1', 'capacity': 120000) AS standard_object;
SELECT JSON_ARRAYAGG(code ORDER BY code) AS warehouse_codes FROM logistics.warehouses;

-- ---------------------------------------------------------------------
-- [Q12.17] Query functions with defaults and error handling
-- Keywords: JSON_VALUE(), JSON_QUERY(), JSON_EXISTS(), RETURNING, DEFAULT … ON EMPTY   (PG17)
-- Business question: Read the warranty as an integer, defaulting to 0 when missing.
-- ---------------------------------------------------------------------
SELECT name,
       JSON_VALUE(attributes, '$.warranty_months' RETURNING int DEFAULT 0 ON EMPTY) AS warranty_months,
       JSON_QUERY(attributes, '$.specs')                                        AS specs,
       JSON_EXISTS(attributes, '$.specs.ram_gb')                                AS has_ram
FROM catalog.products
WHERE category_id IN (SELECT category_id FROM catalog.categories WHERE slug IN ('laptops', 'cookware'))
LIMIT 6;

-- ---------------------------------------------------------------------
-- [Q12.18] Turn JSON into a relational table in one step
-- Keywords: JSON_TABLE(), COLUMNS, PATH, NESTED PATH, FOR ORDINALITY   (PG17)
-- Business question: Flatten product attributes (one row per connectivity option).
-- ---------------------------------------------------------------------
SELECT p.product_id, jt.*
FROM catalog.products p,
     JSON_TABLE(p.attributes, '$'
         COLUMNS (
             color    text PATH '$.color',
             warranty int  PATH '$.warranty_months',
             ram_gb   int  PATH '$.specs.ram_gb',
             NESTED PATH '$.connectivity[*]' COLUMNS (
                 option_no FOR ORDINALITY,
                 option    text PATH '$'
             )
         )) AS jt
WHERE p.attributes ? 'connectivity'
ORDER BY p.product_id, jt.option_no
LIMIT 8;

-- =====================================================================
-- SECTION: Arrays
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q12.19] Array literals, subscripts and slices (1-based!)
-- Keywords: ARRAY[], '{}' literal, [n], [m:n], array_length(), cardinality()
-- ---------------------------------------------------------------------
SELECT ARRAY['a', 'b', 'c']                 AS constructor,
       '{10,20,30}'::int[]                  AS literal,
       (ARRAY['a', 'b', 'c'])[1]            AS first,
       (ARRAY['a', 'b', 'c', 'd'])[2:3]     AS slice,
       array_length(ARRAY[1, 2, 3], 1)      AS length_dim1,
       cardinality(ARRAY[[1, 2], [3, 4]])   AS total_elements;
SELECT name, tags, tags[1] AS first_tag, cardinality(tags) AS tag_count
FROM catalog.products WHERE cardinality(tags) >= 3 LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q12.20] Search inside arrays
-- Keywords: = ANY(array), @>, <@, && (overlap)
-- Business question: Products tagged 'gift'; tagged both 'gift' and 'premium'; tagged any sale-ish tag.
-- ---------------------------------------------------------------------
SELECT count(*) FILTER (WHERE 'gift' = ANY (tags))                         AS gift,
       count(*) FILTER (WHERE tags @> ARRAY['gift', 'premium'])            AS gift_and_premium,
       count(*) FILTER (WHERE tags && ARRAY['sale', 'budget'])             AS sale_or_budget,
       count(*) FILTER (WHERE tags <@ ARRAY['new', 'trending', 'gift'])    AS only_from_list   -- note: empty arrays count too!
FROM catalog.products;

-- ---------------------------------------------------------------------
-- [Q12.21] Modify arrays
-- Keywords: array_append(), array_prepend(), array_cat(), ||, array_remove(), array_replace(), trim_array()
-- ---------------------------------------------------------------------
SELECT array_append(ARRAY['new'], 'gift')                AS appended,
       array_prepend('hot', ARRAY['new'])                AS prepended,
       array_cat(ARRAY['a'], ARRAY['b', 'c'])            AS concatenated,
       ARRAY['a'] || 'b'::text || ARRAY['c']             AS with_operator,   -- untyped 'b' would be read as an array literal
       array_remove(ARRAY['sale', 'gift', 'sale'], 'sale') AS removed,
       array_replace(ARRAY['sale', 'gift'], 'sale', 'deal') AS replaced,
       trim_array(ARRAY[1, 2, 3, 4], 2)                  AS trimmed;   -- PG14+

-- ---------------------------------------------------------------------
-- [Q12.22] Find positions
-- Keywords: array_position(), array_positions()
-- ---------------------------------------------------------------------
SELECT array_position(ARRAY['S', 'M', 'L', 'XL'], 'L')          AS pos_of_L,
       array_positions(ARRAY['sale', 'gift', 'sale'], 'sale')  AS all_positions;

-- ---------------------------------------------------------------------
-- [Q12.23] Expand arrays to rows, with position; zip several arrays
-- Keywords: unnest(), WITH ORDINALITY, unnest(a, b)
-- Business question: List each review image with its index; pair sizes with prices.
-- ---------------------------------------------------------------------
SELECT r.review_id, img.url, img.idx
FROM catalog.reviews r
CROSS JOIN LATERAL unnest(r.image_urls) WITH ORDINALITY AS img(url, idx)
LIMIT 3;
SELECT * FROM unnest(ARRAY['S', 'M', 'L'], ARRAY[499, 549, 599]) AS t(size, price);

-- ---------------------------------------------------------------------
-- [Q12.24] Arrays ⇄ text, comparison and sorting
-- Keywords: array_to_string(), array comparison, ORDER BY array, array_agg(DISTINCT)
-- ---------------------------------------------------------------------
SELECT array_to_string(ARRAY['red', NULL, 'blue'], ', ', '?') AS joined_with_null_marker,
       ARRAY[1, 2, 3] = ARRAY[1, 2, 3] AS equal,
       ARRAY[1, 2, 3] < ARRAY[1, 3]    AS lexicographic_less;
SELECT tags, count(*) AS products
FROM catalog.products
WHERE cardinality(tags) = 2
GROUP BY tags
ORDER BY products DESC
LIMIT 5;
