-- =====================================================================
--  Chapter 17 · Triggers
--  Trigger functions live in schema app with prefix trg_.
--  KEPT after this chapter (safe, useful): updated_at, audit log, price history,
--  order status history. DEMO triggers are dropped at the end.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS app;

-- =====================================================================
-- SECTION: BEFORE row triggers
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q17.01] Keep updated_at current automatically
-- Keywords: CREATE FUNCTION … RETURNS trigger, NEW, BEFORE UPDATE, FOR EACH ROW, CREATE OR REPLACE TRIGGER
-- Note: A BEFORE trigger can modify NEW before it is written; it must RETURN NEW (or NULL to skip the row).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.trg_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON core.users      FOR EACH ROW EXECUTE FUNCTION app.trg_set_updated_at();
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON catalog.products FOR EACH ROW EXECUTE FUNCTION app.trg_set_updated_at();
CREATE OR REPLACE TRIGGER set_updated_at BEFORE UPDATE ON sales.orders     FOR EACH ROW EXECUTE FUNCTION app.trg_set_updated_at();
BEGIN;
UPDATE core.users SET full_name = initcap(full_name) WHERE user_id = 97 RETURNING full_name, updated_at;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q17.02] Normalise and validate data on the way in
-- Keywords: BEFORE INSERT OR UPDATE, TG_OP, RAISE EXCEPTION in trigger
-- Business question: Store names are trimmed/collapsed, and slugs are generated if missing.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.trg_normalise_seller()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.store_name := regexp_replace(trim(NEW.store_name), '\s+', ' ', 'g');
    IF TG_OP = 'INSERT' AND (NEW.slug IS NULL OR NEW.slug = '') THEN
        NEW.slug := trim(BOTH '-' FROM lower(regexp_replace(NEW.store_name, '[^A-Za-z0-9]+', '-', 'g')));
    END IF;
    IF NEW.commission_rate > 0.30 AND NOT NEW.is_verified THEN
        RAISE EXCEPTION 'Unverified sellers cannot have commission above 30%% (got %)', NEW.commission_rate;
    END IF;
    RETURN NEW;
END;
$$;
CREATE OR REPLACE TRIGGER normalise_seller BEFORE INSERT OR UPDATE ON core.sellers
    FOR EACH ROW EXECUTE FUNCTION app.trg_normalise_seller();
BEGIN;
INSERT INTO core.sellers (owner_user_id, store_name, slug)
VALUES (4999, '   The   Chai   Corner  ', '')
RETURNING store_name, slug;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q17.03] Fire only when specific columns change, and only if a condition holds
-- Keywords: AFTER UPDATE OF column, WHEN (OLD.x IS DISTINCT FROM NEW.x), OLD
-- Business question: Record every product price change in catalog.price_history automatically.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.trg_log_price_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO catalog.price_history (product_id, old_price, new_price)
    VALUES (NEW.product_id, OLD.base_price, NEW.base_price);
    RETURN NULL;                 -- return value of AFTER row triggers is ignored
END;
$$;
CREATE OR REPLACE TRIGGER log_price_change
    AFTER UPDATE OF base_price ON catalog.products
    FOR EACH ROW
    WHEN (OLD.base_price IS DISTINCT FROM NEW.base_price)
    EXECUTE FUNCTION app.trg_log_price_change();
BEGIN;
UPDATE catalog.products SET base_price = base_price + 100 WHERE product_id = 2;
UPDATE catalog.products SET base_price = base_price WHERE product_id = 3;          -- no change → no history row
SELECT product_id, old_price, new_price FROM catalog.price_history
WHERE product_id IN (2, 3) AND changed_at = now();      -- rows written in THIS transaction: only product 2
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q17.04] Maintain a history table for a state machine
-- Keywords: AFTER UPDATE OF status, OLD.status, NEW.status
-- Business question: Every order status change goes into sales.order_status_history.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.trg_order_status_history()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO sales.order_status_history (order_id, from_status, to_status)
    VALUES (NEW.order_id, OLD.status, NEW.status);
    RETURN NULL;
END;
$$;
CREATE OR REPLACE TRIGGER order_status_history
    AFTER UPDATE OF status ON sales.orders
    FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION app.trg_order_status_history();
BEGIN;
UPDATE sales.orders SET status = 'cancelled' WHERE order_id = (SELECT min(order_id) FROM sales.orders WHERE status = 'pending');
SELECT order_id, from_status, to_status FROM sales.order_status_history ORDER BY history_id DESC LIMIT 1;
ROLLBACK;

-- =====================================================================
-- SECTION: Generic audit trigger
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q17.05] One trigger function for many tables
-- Keywords: AFTER INSERT OR UPDATE OR DELETE, TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV, to_jsonb(OLD/NEW)
-- Business question: Keep a full change log of coupons and sellers in audit.audit_log.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.trg_audit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    pk_col text := TG_ARGV[0];                      -- argument given in CREATE TRIGGER
    row_data jsonb := to_jsonb(CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END);
BEGIN
    INSERT INTO audit.audit_log (table_name, operation, row_pk, old_data, new_data)
    VALUES (TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
            TG_OP,
            row_data ->> pk_col,
            CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP IN ('UPDATE', 'INSERT') THEN to_jsonb(NEW) END);
    RETURN NULL;
END;
$$;
CREATE OR REPLACE TRIGGER audit AFTER INSERT OR UPDATE OR DELETE ON sales.coupons
    FOR EACH ROW EXECUTE FUNCTION app.trg_audit('coupon_id');
CREATE OR REPLACE TRIGGER audit AFTER INSERT OR UPDATE OR DELETE ON core.sellers
    FOR EACH ROW EXECUTE FUNCTION app.trg_audit('seller_id');
BEGIN;
UPDATE sales.coupons SET discount_value = 12 WHERE code = 'WELCOME10';
DELETE FROM sales.coupons WHERE code = 'NEWYEAR30';
SELECT table_name, operation, row_pk, changed_by FROM audit.audit_log ORDER BY audit_id DESC LIMIT 2;

-- ---------------------------------------------------------------------
-- [Q17.06] Diff only the changed fields of an UPDATE from the audit log
-- Keywords: jsonb_each(), IS DISTINCT FROM, audit diff
-- ---------------------------------------------------------------------
SELECT n.key AS field, o.value AS old_value, n.value AS new_value
FROM audit.audit_log a
CROSS JOIN LATERAL jsonb_each(a.new_data) n
JOIN LATERAL jsonb_each(a.old_data) o ON o.key = n.key
WHERE a.operation = 'UPDATE' AND a.table_name = 'sales.coupons'
  AND o.value IS DISTINCT FROM n.value
ORDER BY a.audit_id DESC
LIMIT 5;
ROLLBACK;

-- =====================================================================
-- SECTION: Statement-level triggers & transition tables
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q17.07] Run once per statement and see ALL affected rows
-- Keywords: FOR EACH STATEMENT, REFERENCING OLD TABLE AS / NEW TABLE AS (transition tables)
-- Business question: Log one summary line per bulk stock update (how many rows, net unit change).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit.stock_batches (
    batch_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rows_changed int,
    net_change   bigint,
    at           timestamptz DEFAULT now()
);
CREATE OR REPLACE FUNCTION app.trg_stock_batch_summary()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO audit.stock_batches (rows_changed, net_change)
    SELECT count(*), sum(n.quantity_on_hand - o.quantity_on_hand)
    FROM new_rows n JOIN old_rows o USING (variant_id, warehouse_id);
    RETURN NULL;
END;
$$;
CREATE OR REPLACE TRIGGER stock_batch_summary
    AFTER UPDATE ON logistics.inventory
    REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
    FOR EACH STATEMENT
    EXECUTE FUNCTION app.trg_stock_batch_summary();
BEGIN;
UPDATE logistics.inventory SET quantity_on_hand = quantity_on_hand + 10 WHERE warehouse_id = 8;
SELECT rows_changed, net_change FROM audit.stock_batches ORDER BY batch_id DESC LIMIT 1;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q17.08] TRUNCATE triggers (statement level only)
-- Keywords: BEFORE TRUNCATE, TG_WHEN, TG_LEVEL
-- Business question: Forbid TRUNCATE on the audit log.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.trg_forbid()
RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION '% % on % is not allowed (%/%)', TG_WHEN, TG_OP, TG_TABLE_NAME, TG_LEVEL, TG_WHEN;
END;
$$;
CREATE OR REPLACE TRIGGER no_truncate BEFORE TRUNCATE ON audit.audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION app.trg_forbid();
DO $$
BEGIN
    TRUNCATE audit.audit_log;
EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

-- =====================================================================
-- SECTION: Special trigger kinds
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q17.09] Make a complex view writable
-- Keywords: INSTEAD OF INSERT, trigger on a view
-- Business question: The mobile app adds to cart by user_id + SKU; the view hides cart/variant ids.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW app.cart_lines AS
SELECT c.user_id, v.sku, ci.quantity, ci.added_at
FROM sales.carts c
JOIN sales.cart_items ci USING (cart_id)
JOIN catalog.product_variants v USING (variant_id);

CREATE OR REPLACE FUNCTION app.trg_cart_lines_insert()
RETURNS trigger LANGUAGE plpgsql
AS $$
DECLARE
    v_cart bigint;
BEGIN
    INSERT INTO sales.carts (user_id) VALUES (NEW.user_id)
    ON CONFLICT (user_id) DO UPDATE SET updated_at = now()
    RETURNING cart_id INTO v_cart;
    INSERT INTO sales.cart_items (cart_id, variant_id, quantity)
    SELECT v_cart, variant_id, COALESCE(NEW.quantity, 1) FROM catalog.product_variants WHERE sku = NEW.sku
    ON CONFLICT (cart_id, variant_id) DO UPDATE SET quantity = least(sales.cart_items.quantity + EXCLUDED.quantity, 10);
    RETURN NEW;
END;
$$;
CREATE OR REPLACE TRIGGER cart_lines_insert INSTEAD OF INSERT ON app.cart_lines
    FOR EACH ROW EXECUTE FUNCTION app.trg_cart_lines_insert();
BEGIN;
INSERT INTO app.cart_lines (user_id, sku, quantity) VALUES (4998, 'SKU-000001-V1', 2);
SELECT * FROM app.cart_lines WHERE user_id = 4998;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q17.10] Deferred constraint triggers: check rules at COMMIT
-- Keywords: CREATE CONSTRAINT TRIGGER, DEFERRABLE INITIALLY DEFERRED
-- Business question: An order must have at least one item by the time the transaction commits.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.trg_order_has_items()
RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sales.order_items WHERE order_id = NEW.order_id) THEN
        RAISE EXCEPTION 'Order % has no items', NEW.order_id;
    END IF;
    RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS order_has_items ON sales.orders;
CREATE CONSTRAINT TRIGGER order_has_items
    AFTER INSERT ON sales.orders
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION app.trg_order_has_items();
DO $$
BEGIN
    -- items are added later in the same transaction → fine; here we never add one → fails at "commit"
    INSERT INTO sales.orders (order_number, user_id) VALUES ('SS-EMPTY-DEMO', 1);
    SET CONSTRAINTS sales.order_has_items IMMEDIATE;          -- force the deferred check now
EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'Expected error: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- [Q17.11] Temporarily switch triggers off (e.g. during a bulk load)
-- Keywords: ALTER TABLE … DISABLE TRIGGER / ENABLE TRIGGER, session_replication_role
-- ---------------------------------------------------------------------
BEGIN;
ALTER TABLE catalog.products DISABLE TRIGGER log_price_change;
UPDATE catalog.products SET base_price = base_price * 1.01 WHERE product_id = 4;   -- no history row
ALTER TABLE catalog.products ENABLE TRIGGER log_price_change;
SELECT tgname, tgenabled FROM pg_trigger WHERE tgrelid = 'catalog.products'::regclass AND NOT tgisinternal;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q17.12] Firing order and recursion guards
-- Keywords: alphabetical firing order, pg_trigger_depth()
-- Note: Triggers of the same kind fire in alphabetical order by name.
--       pg_trigger_depth() = how deeply nested we are; use it to stop trigger loops.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.trg_show_depth()
RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    RAISE NOTICE 'trigger % fired at depth %', TG_NAME, pg_trigger_depth();
    RETURN NEW;
END;
$$;
CREATE OR REPLACE TRIGGER a_first  BEFORE UPDATE ON logistics.warehouses FOR EACH ROW EXECUTE FUNCTION app.trg_show_depth();
CREATE OR REPLACE TRIGGER b_second BEFORE UPDATE ON logistics.warehouses FOR EACH ROW EXECUTE FUNCTION app.trg_show_depth();
BEGIN;
UPDATE logistics.warehouses SET capacity = capacity WHERE warehouse_id = 1;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q17.13] Event triggers react to DDL
-- Keywords: CREATE EVENT TRIGGER, ddl_command_end, pg_event_trigger_ddl_commands(), TG_TAG
-- Business question: Log every schema change (who, what, when).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit.ddl_log (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    command_tag text, object_identity text, by_user text DEFAULT current_user, at timestamptz DEFAULT now());
CREATE OR REPLACE FUNCTION app.trg_log_ddl()
RETURNS event_trigger LANGUAGE plpgsql
AS $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        INSERT INTO audit.ddl_log (command_tag, object_identity) VALUES (r.command_tag, r.object_identity);
    END LOOP;
END;
$$;
DROP EVENT TRIGGER IF EXISTS log_ddl;
CREATE EVENT TRIGGER log_ddl ON ddl_command_end EXECUTE FUNCTION app.trg_log_ddl();
CREATE TABLE IF NOT EXISTS app.event_trigger_demo (id int);
ALTER TABLE app.event_trigger_demo ADD COLUMN IF NOT EXISTS note text;
SELECT command_tag, object_identity FROM audit.ddl_log ORDER BY id DESC LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q17.14] List all triggers
-- Keywords: pg_trigger, information_schema.triggers, pg_event_trigger, pg_get_triggerdef()
-- ---------------------------------------------------------------------
SELECT event_object_schema || '.' || event_object_table AS table_name, trigger_name,
       action_timing, string_agg(event_manipulation, '/') AS events, action_orientation
FROM information_schema.triggers
WHERE trigger_schema NOT IN ('pg_catalog')
GROUP BY 1, 2, 3, 5
ORDER BY 1, 2;
SELECT evtname, evtevent, evtenabled FROM pg_event_trigger;
SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgname = 'log_price_change';

-- =====================================================================
-- SECTION: Cleanup of demo-only triggers
-- =====================================================================
DROP TRIGGER IF EXISTS a_first ON logistics.warehouses;
DROP TRIGGER IF EXISTS b_second ON logistics.warehouses;
DROP TRIGGER IF EXISTS order_has_items ON sales.orders;      -- other chapters create orders step by step
DROP EVENT TRIGGER IF EXISTS log_ddl;
DROP TABLE IF EXISTS app.event_trigger_demo;
