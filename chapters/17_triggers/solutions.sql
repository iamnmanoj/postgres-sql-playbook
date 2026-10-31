-- =====================================================================
--  Chapter 17 · Solutions — triggers
--  All solution triggers are created inside BEGIN … ROLLBACK (DDL is transactional in PostgreSQL!)
--  so nothing is left behind.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS app;
CREATE OR REPLACE FUNCTION app.trg_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $$;

-- [E17.01] Reuse the updated_at trigger function
-- Keywords: CREATE TRIGGER, BEFORE UPDATE
BEGIN;
CREATE TRIGGER ex17_inventory_updated_at BEFORE UPDATE ON logistics.inventory
    FOR EACH ROW EXECUTE FUNCTION app.trg_set_updated_at();
UPDATE logistics.inventory SET reorder_level = reorder_level WHERE variant_id = 1 RETURNING warehouse_id, updated_at;
ROLLBACK;

-- [E17.02] Keep seller rating in sync
-- Keywords: AFTER INSERT OR DELETE, TG_OP, OLD/NEW
CREATE OR REPLACE FUNCTION app.trg_ex17_seller_rating()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_product bigint := CASE WHEN TG_OP = 'DELETE' THEN OLD.product_id ELSE NEW.product_id END;
BEGIN
    UPDATE core.sellers s
    SET rating_avg = (SELECT round(avg(r.rating), 2) FROM catalog.reviews r
                      JOIN catalog.products p USING (product_id) WHERE p.seller_id = s.seller_id)
    WHERE s.seller_id = (SELECT seller_id FROM catalog.products WHERE product_id = v_product);
    RETURN NULL;
END; $$;
BEGIN;
CREATE TRIGGER ex17_seller_rating AFTER INSERT OR DELETE ON catalog.reviews
    FOR EACH ROW EXECUTE FUNCTION app.trg_ex17_seller_rating();
SELECT s.rating_avg AS before FROM core.sellers s JOIN catalog.products p USING (seller_id) WHERE p.product_id = 1;
INSERT INTO catalog.reviews (product_id, user_id, rating, title)                 -- 100 one-star reviews
SELECT 1, user_id, 1, 'Terrible' FROM core.users WHERE user_id BETWEEN 4801 AND 4900
ON CONFLICT (product_id, user_id) DO NOTHING;
SELECT s.rating_avg AS after FROM core.sellers s JOIN catalog.products p USING (seller_id) WHERE p.product_id = 1;
ROLLBACK;

-- [E17.03] Block deletes of ordered products
-- Keywords: BEFORE DELETE, RAISE EXCEPTION, RETURN OLD
CREATE OR REPLACE FUNCTION app.trg_ex17_protect_ordered_product()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM sales.order_items oi JOIN catalog.product_variants v USING (variant_id)
               WHERE v.product_id = OLD.product_id) THEN
        RAISE EXCEPTION 'Product % has orders; deactivate it instead (is_active = false)', OLD.product_id
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN OLD;              -- BEFORE DELETE must return OLD to let the delete proceed
END; $$;
BEGIN;
CREATE TRIGGER ex17_protect BEFORE DELETE ON catalog.products
    FOR EACH ROW EXECUTE FUNCTION app.trg_ex17_protect_ordered_product();
DO $$
BEGIN
    DELETE FROM catalog.products WHERE product_id = 1;
EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'Blocked: %', SQLERRM;
END $$;
ROLLBACK;

-- [E17.04] Statement-level summary with a transition table
-- Keywords: FOR EACH STATEMENT, REFERENCING NEW TABLE
CREATE OR REPLACE FUNCTION app.trg_ex17_items_summary()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n bigint; rev numeric;
BEGIN
    SELECT count(*), sum(line_total) INTO n, rev FROM inserted;
    RAISE NOTICE 'Inserted % items worth ₹%', n, rev;
    RETURN NULL;
END; $$;
BEGIN;
CREATE TRIGGER ex17_items_summary AFTER INSERT ON sales.order_items
    REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE FUNCTION app.trg_ex17_items_summary();
INSERT INTO sales.order_items (order_id, variant_id, seller_id, quantity, unit_price)
SELECT 1, v.variant_id, p.seller_id, 1, p.base_price
FROM catalog.product_variants v JOIN catalog.products p USING (product_id)
WHERE v.variant_id BETWEEN 3000 AND 3002;
ROLLBACK;

-- [E17.05] Cascading business triggers
-- Keywords: AFTER UPDATE OF status … WHEN, trigger calling trigger
CREATE OR REPLACE FUNCTION app.trg_ex17_delivery_completes_order()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE sales.orders SET status = 'delivered' WHERE order_id = NEW.order_id AND status <> 'delivered';
    RETURN NULL;
END; $$;
BEGIN;
CREATE TRIGGER ex17_delivery AFTER UPDATE OF status ON logistics.shipments
    FOR EACH ROW WHEN (NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION app.trg_ex17_delivery_completes_order();
UPDATE logistics.shipments SET status = 'delivered', delivered_at = now()
WHERE shipment_id = (SELECT min(shipment_id) FROM logistics.shipments WHERE status = 'in_transit')
RETURNING order_id \gset
SELECT order_id, status FROM sales.orders WHERE order_id = :order_id;
SELECT from_status, to_status FROM sales.order_status_history WHERE order_id = :order_id ORDER BY history_id DESC LIMIT 1;
ROLLBACK;
