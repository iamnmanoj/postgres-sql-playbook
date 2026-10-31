-- =====================================================================
--  Chapter 10 · Solutions — UPDATE, DELETE, UPSERT, MERGE
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS playground_10;

-- [E10.01] Mark notifications read
-- Keywords: UPDATE, IS NULL, RETURNING
BEGIN;
WITH r AS (
    UPDATE core.notifications SET read_at = now()
    WHERE user_id = 8 AND read_at IS NULL
    RETURNING notification_id
)
SELECT count(*) AS marked_read FROM r;
ROLLBACK;

-- [E10.02] Deactivate products without active variants
-- Keywords: UPDATE … WHERE NOT EXISTS, RETURNING
BEGIN;
UPDATE catalog.products p
SET is_active = false
WHERE p.is_active
  AND NOT EXISTS (SELECT 1 FROM catalog.product_variants v WHERE v.product_id = p.product_id AND v.is_active)
RETURNING p.product_id;
ROLLBACK;

-- [E10.03] updated_at from latest price change
-- Keywords: UPDATE … FROM, aggregate subquery
BEGIN;
UPDATE catalog.products p
SET updated_at = ph.last_change
FROM (SELECT product_id, max(changed_at) AS last_change FROM catalog.price_history GROUP BY product_id) ph
WHERE ph.product_id = p.product_id;
ROLLBACK;

-- [E10.04] Remove votes by banned users
-- Keywords: DELETE … USING
BEGIN;
DELETE FROM catalog.review_votes rv
USING core.users u
WHERE u.user_id = rv.user_id AND u.status IN ('suspended', 'deleted');
ROLLBACK;

-- [E10.05] Cart upsert with a cap
-- Keywords: ON CONFLICT DO NOTHING, ON CONFLICT DO UPDATE, EXCLUDED, least()
BEGIN;
INSERT INTO sales.carts (user_id) VALUES (15) ON CONFLICT (user_id) DO NOTHING;
INSERT INTO sales.cart_items AS ci (cart_id, variant_id, quantity)
SELECT cart_id, 3, 1 FROM sales.carts WHERE user_id = 15
ON CONFLICT (cart_id, variant_id)
DO UPDATE SET quantity = least(ci.quantity + EXCLUDED.quantity, 10), added_at = now()
RETURNING *;
ROLLBACK;

-- [E10.06] Fix denormalised helpful_count
-- Keywords: UPDATE … FROM (self-join for old value), RETURNING
BEGIN;
UPDATE catalog.reviews r
SET helpful_count = v.cnt
FROM (SELECT review_id, count(*) FILTER (WHERE is_helpful) AS cnt FROM catalog.review_votes GROUP BY review_id) v,
     catalog.reviews old
WHERE v.review_id = r.review_id
  AND old.review_id = r.review_id
  AND r.helpful_count <> v.cnt
RETURNING r.review_id, old.helpful_count AS old_value, r.helpful_count AS new_value;
ROLLBACK;

-- [E10.07] MERGE a price feed
-- Keywords: MERGE, WHEN MATCHED AND, DO NOTHING, merge_action()
DROP TABLE IF EXISTS playground_10.price_feed;
CREATE TABLE playground_10.price_feed (sku text PRIMARY KEY, price numeric(12, 2));
INSERT INTO playground_10.price_feed
SELECT sku, base_price + 100 FROM catalog.products ORDER BY product_id LIMIT 3;
INSERT INTO playground_10.price_feed
SELECT sku, base_price FROM catalog.products ORDER BY product_id OFFSET 3 LIMIT 1;   -- unchanged
INSERT INTO playground_10.price_feed VALUES ('SKU-UNKNOWN', 999);
BEGIN;
MERGE INTO catalog.products p
USING playground_10.price_feed f ON f.sku = p.sku
WHEN MATCHED AND p.base_price <> f.price THEN UPDATE SET base_price = f.price, updated_at = now()
WHEN MATCHED THEN DO NOTHING
RETURNING merge_action(), p.sku, p.base_price;
ROLLBACK;
