-- Products, variants, images, price history, inventory, stock movements.

-- 3,000 products. Sellers are picked with a skew (power(random(), 1.5)) so a few
-- sellers own many products; sellers 191-200 own none (useful for anti-joins).
WITH picks AS (
    SELECT g,
           1 + floor((SELECT count(*) FROM seed_leaf) * random())::int AS leaf_rn,
           1 + floor(190 * power(random(), 1.5))::bigint               AS seller_id,
           random() AS r_noun, random() AS r_brand, random() AS r_price, random() AS r_color,
           random() AS r_f1, random() AS r_f2, random() AS r_use, random() AS r_unbranded,
           (ARRAY['Pro','Max','Lite','Neo','Air','Plus','Ultra','Mini'])[1 + floor(random() * 8)::int]
               || ' ' || (10 + floor(random() * 90))::int AS model,
           (ARRAY['Silent','Hidden','Golden','Last','Brave','Midnight','Little','Endless','Curious','Wild'])[1 + floor(random() * 10)::int] AS adjective
    FROM generate_series(1, 3000) AS g
), shaped AS (
    SELECT p.g, p.seller_id, l.category_id, l.kind,
           CASE WHEN l.kind = 'books' OR p.r_unbranded < 0.08 THEN NULL
                ELSE k.brand_ids[1 + floor(p.r_brand * cardinality(k.brand_ids))::int] END AS brand_id,
           l.nouns[1 + floor(p.r_noun * cardinality(l.nouns))::int] AS noun,
           k.colors[1 + floor(p.r_color * cardinality(k.colors))::int] AS color,
           k.features[1 + floor(p.r_f1 * cardinality(k.features))::int] AS feature1,
           k.features[1 + floor(p.r_f2 * cardinality(k.features))::int] AS feature2,
           k.uses[1 + floor(p.r_use * cardinality(k.uses))::int] AS use_case,
           round(l.min_price + p.r_price * p.r_price * (l.max_price - l.min_price)) - 0.01 AS price,
           p.model, p.adjective
    FROM picks p
    JOIN seed_leaf l ON l.rn = p.leaf_rn
    JOIN seed_kind k ON k.kind = l.kind
), named AS (
    SELECT s.*,
           CASE WHEN s.kind = 'books' THEN 'The ' || s.adjective || ' ' || s.noun
                WHEN s.brand_id IS NULL THEN initcap(s.color) || ' ' || s.noun
                ELSE b.name || ' ' || s.noun || ' ' || s.model END AS product_name
    FROM shaped s
    LEFT JOIN catalog.brands b ON b.brand_id = s.brand_id
)
INSERT INTO catalog.products (seller_id, category_id, brand_id, sku, name, description, base_price,
                              attributes, tags, weight_grams, is_active, created_at, updated_at)
SELECT n.seller_id, n.category_id, n.brand_id,
       'SKU-' || lpad(n.g::text, 6, '0'),
       n.product_name,
       CASE WHEN n.g % 40 = 0 THEN NULL     -- some products have no description
            ELSE 'The ' || n.product_name || ' offers ' || n.feature1 || ' and ' || n.feature2
                 || '. Perfect for ' || n.use_case || '.' END,
       n.price,
       jsonb_strip_nulls(jsonb_build_object('color', n.color) ||
           CASE n.kind
             WHEN 'electronics' THEN jsonb_build_object(
                  'warranty_months', (ARRAY[6, 12, 12, 24])[1 + n.g % 4],
                  'connectivity', (ARRAY['["bluetooth"]','["bluetooth","wifi"]','["wifi","5g","bluetooth"]','["usb-c"]'])[1 + n.g % 4]::jsonb,
                  'specs', jsonb_build_object('battery_mah', CASE WHEN n.g % 3 > 0 THEN 1000 * (2 + n.g % 5) END,
                                              'ram_gb', CASE WHEN n.noun ~ 'Phone|Laptop|Tablet|book' THEN (ARRAY[4, 8, 16, 32])[1 + n.g % 4] END))
             WHEN 'fashion' THEN jsonb_build_object(
                  'material', (ARRAY['cotton','polyester','denim','leather','linen'])[1 + n.g % 5],
                  'fit', (ARRAY['slim','regular','relaxed'])[1 + n.g % 3],
                  'care', '["machine wash","do not bleach"]'::jsonb)
             WHEN 'home' THEN jsonb_build_object(
                  'material', (ARRAY['steel','wood','plastic','glass'])[1 + n.g % 4],
                  'power_watts', CASE WHEN n.noun ~ 'Grinder|Fryer|Kettle|Cooktop' THEN 500 + 250 * (n.g % 7) END,
                  'warranty_months', (ARRAY[12, 24, 60])[1 + n.g % 3])
             WHEN 'books' THEN jsonb_build_object(
                  'author', (SELECT first_names[1 + n.g % 40] || ' ' || last_names[1 + n.g % 30] FROM seed_names),
                  'pages', 80 + (n.g * 37) % 800,
                  'language', (ARRAY['English','English','Hindi','Tamil'])[1 + n.g % 4],
                  'format', (ARRAY['paperback','hardcover','ebook'])[1 + n.g % 3],
                  'isbn', '978' || lpad(((n.g::bigint * 7919) % 10000000000)::text, 10, '0'))
             WHEN 'beauty' THEN jsonb_build_object('volume_ml', (ARRAY[30, 50, 100, 200])[1 + n.g % 4], 'skin_type', (ARRAY['all','dry','oily'])[1 + n.g % 3])
             WHEN 'toys' THEN jsonb_build_object('age_group', (ARRAY['3+','6+','8+','12+'])[1 + n.g % 4], 'pieces', 20 + (n.g % 30) * 10)
             ELSE jsonb_build_object('material', (ARRAY['rubber','steel','nylon','aluminium'])[1 + n.g % 4])
           END),
       (SELECT coalesce(array_agg(t ORDER BY t), '{}')
          FROM unnest(ARRAY['bestseller','new','eco-friendly','gift','sale','premium','budget','trending']) AS t
         WHERE random() < 0.18 AND n.g > 0),                     -- "n.g > 0" makes the subquery re-run per row
       CASE WHEN n.kind = 'books' THEN 200 + n.g % 800 ELSE 100 + (n.g * 53) % 9000 END,
       n.g % 37 <> 0,                                              -- ~3% inactive
       created_at, created_at + random() * (now() - created_at)
FROM named n
JOIN LATERAL (SELECT s.joined_at + random() * (now() - s.joined_at) * 0.6 AS created_at
              FROM core.sellers s WHERE s.seller_id = n.seller_id) c ON true
ORDER BY created_at;

-- Variants: fashion -> sizes, electronics -> colour/storage, others -> 1-2 colours
INSERT INTO catalog.product_variants (product_id, sku, options, price_delta, is_active)
SELECT p.product_id,
       p.sku || '-V' || v.n,
       CASE l.kind
         WHEN 'fashion'     THEN jsonb_build_object('size', (ARRAY['S','M','L','XL','XXL'])[v.n], 'color', p.attributes->>'color')
         WHEN 'electronics' THEN jsonb_build_object('color', (ARRAY['black','silver','blue'])[v.n])
                                 || CASE WHEN p.attributes->'specs' ? 'ram_gb' THEN jsonb_build_object('storage_gb', (ARRAY[128, 256, 512])[v.n]) ELSE '{}' END
         ELSE CASE WHEN v.n = 1 THEN '{}'::jsonb ELSE jsonb_build_object('color', (ARRAY['red','green'])[v.n - 1]) END
       END,
       CASE WHEN v.n = 1 THEN 0
            WHEN l.kind = 'electronics' THEN round(p.base_price * 0.1 * (v.n - 1), -1)
            WHEN l.kind = 'fashion' AND v.n >= 4 THEN 100
            ELSE 0 END,
       (p.product_id + v.n) % 41 <> 0
FROM catalog.products p
JOIN seed_leaf l USING (category_id)
CROSS JOIN LATERAL generate_series(1, CASE l.kind WHEN 'fashion' THEN 2 + (p.product_id % 4)::int
                                                  WHEN 'electronics' THEN 1 + (p.product_id % 3)::int
                                                  ELSE 1 + (p.product_id % 2)::int END) AS v(n)
ORDER BY p.product_id, v.n;

-- 1-5 images per product (a few products have none)
INSERT INTO catalog.product_images (product_id, url, position, alt_text)
SELECT p.product_id,
       'https://cdn.shopsphere.test/p/' || p.product_id || '/' || pos || '.jpg',
       pos,
       CASE WHEN pos = 1 THEN p.name END
FROM catalog.products p
CROSS JOIN LATERAL generate_series(1, (p.product_id % 6)::int) AS pos;

-- Price history: a chain of changes ending at today's base_price
INSERT INTO catalog.price_history (product_id, old_price, new_price, changed_at)
SELECT p.product_id,
       round(p.base_price * (1 + dir * 0.06 * (cnt - k + 1)), 2),
       round(p.base_price * (1 + dir * 0.06 * (cnt - k)), 2),
       p.created_at + (now() - p.created_at) * k / (cnt + 1)
FROM catalog.products p
CROSS JOIN LATERAL (SELECT (p.product_id % 4)::int AS cnt, CASE WHEN p.product_id % 2 = 0 THEN 1 ELSE -1 END AS dir) x
CROSS JOIN LATERAL generate_series(1, x.cnt) AS k
WHERE p.product_id % 3 = 0;

-- Inventory: each variant stocked in 1-3 warehouses
INSERT INTO logistics.inventory (variant_id, warehouse_id, quantity_on_hand, quantity_reserved, reorder_level, updated_at)
SELECT variant_id, warehouse_id, on_hand,
       floor(random() * least(on_hand, 15))::int,
       (ARRAY[10, 20, 50])[1 + (variant_id % 3)::int],
       now() - random() * interval '30 days'
FROM (
    SELECT v.variant_id,
           (1 + (v.variant_id + w.n * 3) % 8)::smallint AS warehouse_id,
           CASE WHEN random() < 0.06 THEN 0 ELSE floor(random() * 500)::int END AS on_hand
    FROM catalog.product_variants v
    CROSS JOIN LATERAL generate_series(1, 1 + (v.variant_id % 3)::int) AS w(n)
) s;

-- Stock movements: an initial purchase for every stocked row + random adjustments
INSERT INTO logistics.inventory_movements (variant_id, warehouse_id, change, reason, created_at)
SELECT variant_id, warehouse_id, quantity_on_hand + 25, 'purchase', updated_at - interval '90 days'
FROM logistics.inventory WHERE quantity_on_hand > 0;

INSERT INTO logistics.inventory_movements (variant_id, warehouse_id, change, reason, created_at)
SELECT variant_id, warehouse_id,
       CASE WHEN random() < 0.7 THEN -1 - floor(random() * 5)::int ELSE 1 + floor(random() * 5)::int END,
       (ARRAY['sale','sale','return','adjustment','transfer'])[1 + floor(random() * 5)::int],
       updated_at - random() * interval '60 days'
FROM logistics.inventory
WHERE random() < 0.3;
