-- =====================================================================
--  Chapter 12 · Solutions — JSONB & arrays
-- =====================================================================

-- [E12.01] Orders per device
-- Keywords: ->>, GROUP BY
SELECT metadata ->> 'device' AS device, count(*) AS orders
FROM sales.orders
GROUP BY 1
ORDER BY orders DESC;

-- [E12.02] Most-tagged products
-- Keywords: cardinality(), array_to_string()
SELECT name, cardinality(tags) AS tag_count, array_to_string(tags, ', ') AS tag_list
FROM catalog.products
ORDER BY tag_count DESC, product_id
LIMIT 5;

-- [E12.03] Failure reasons
-- Keywords: ->>, GROUP BY
SELECT gateway_response ->> 'error_code' AS error_code, count(*) AS failures
FROM sales.payments
WHERE status = 'failed'
GROUP BY 1
ORDER BY failures DESC;

-- [E12.04] One containment test for nested values
-- Keywords: @>
SELECT count(*) AS newsletter_and_push
FROM core.users
WHERE preferences @> '{"newsletter": true, "notifications": {"push": true}}';

-- [E12.05] Materials of machine-washable products
-- Keywords: ->, @> on a JSON array, ->>
SELECT attributes ->> 'material' AS material, count(*) AS products
FROM catalog.products
WHERE attributes -> 'care' @> '["machine wash"]'
GROUP BY 1
ORDER BY products DESC;

-- [E12.06] Add and remove keys in bulk
-- Keywords: ||, - key, jsonb_build_object()
BEGIN;
WITH a AS (
    UPDATE core.users SET preferences = preferences || jsonb_build_object('loyalty_tier', 'gold')
    WHERE is_prime RETURNING 1
), b AS (
    UPDATE core.users SET preferences = preferences - 'theme'
    WHERE preferences ? 'theme' AND NOT is_prime RETURNING 1
)
SELECT (SELECT count(*) FROM a) AS prime_tagged, (SELECT count(*) FROM b) AS themes_removed_non_prime;
ROLLBACK;
-- Note: two CTEs must not update the same row, so the second one skips Prime users here.

-- [E12.07] JSON_TABLE + aggregation
-- Keywords: JSON_TABLE(), NESTED PATH, GROUP BY
SELECT jt.option, jt.warranty, count(*) AS products
FROM catalog.products p,
     JSON_TABLE(p.attributes, '$' COLUMNS (
         warranty int PATH '$.warranty_months',
         NESTED PATH '$.connectivity[*]' COLUMNS (option text PATH '$'))) jt
WHERE jt.option IS NOT NULL
GROUP BY jt.option, jt.warranty
ORDER BY jt.option, jt.warranty;

-- [E12.08] Similar products by shared tags
-- Keywords: &&, unnest(), INTERSECT inside a scalar subquery
SELECT p.product_id, p.name, p.tags,
       (SELECT count(*) FROM (SELECT unnest(p.tags) INTERSECT SELECT unnest(ref.tags)) s) AS shared
FROM catalog.products p, catalog.products ref
WHERE ref.product_id = 1
  AND p.product_id <> ref.product_id
  AND p.tags && ref.tags
ORDER BY shared DESC, p.product_id
LIMIT 10;

-- [E12.09] Seller JSON documents
-- Keywords: jsonb_build_object(), jsonb_agg(), LATERAL
SELECT jsonb_pretty(jsonb_build_object(
           'store', s.store_name,
           'rating', s.rating_avg,
           'top_products', (SELECT jsonb_agg(jsonb_build_object('name', t.name, 'price', t.base_price) ORDER BY t.base_price DESC)
                            FROM (SELECT name, base_price FROM catalog.products p
                                  WHERE p.seller_id = s.seller_id ORDER BY base_price DESC LIMIT 3) t)
       )) AS seller_doc
FROM core.sellers s
ORDER BY s.seller_id
LIMIT 3;
