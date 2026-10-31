-- =====================================================================
--  Chapter 16 · Functions, procedures & PL/pgSQL
--  Objects live in schema "app" (idempotent: CREATE OR REPLACE / DROP IF EXISTS).
--  Procedures that change data clean up after themselves or are rolled back.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS app;

-- =====================================================================
-- SECTION: SQL functions
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q16.01] A scalar SQL function
-- Keywords: CREATE OR REPLACE FUNCTION, LANGUAGE sql, RETURNS, $1 / named parameters
-- Business question: One place to compute the price of a variant (base + delta).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.variant_price(p_variant_id bigint)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT p.base_price + v.price_delta
    FROM catalog.product_variants v
    JOIN catalog.products p USING (product_id)
    WHERE v.variant_id = p_variant_id
$$;
SELECT variant_id, app.variant_price(variant_id) AS price FROM catalog.product_variants ORDER BY variant_id LIMIT 3;

-- ---------------------------------------------------------------------
-- [Q16.02] Volatility categories tell the planner what a function may do
-- Keywords: IMMUTABLE, STABLE, VOLATILE, STRICT, PARALLEL SAFE
-- Note: IMMUTABLE = same inputs → same output forever (indexable); STABLE = constant within a statement
--       (may read tables); VOLATILE = may change anything (default). STRICT = returns NULL on any NULL input.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.gst_amount(amount numeric, rate numeric DEFAULT 0.18)
RETURNS numeric
LANGUAGE sql
IMMUTABLE STRICT PARALLEL SAFE
AS $$ SELECT round(amount * rate, 2) $$;
SELECT app.gst_amount(1000) AS default_rate, app.gst_amount(1000, 0.05) AS reduced_rate, app.gst_amount(NULL) AS strict_null;
SELECT proname, provolatile, proisstrict, proparallel FROM pg_proc WHERE proname IN ('variant_price', 'gst_amount');

-- ---------------------------------------------------------------------
-- [Q16.03] Calling with named arguments and defaults
-- Keywords: named notation =>, DEFAULT parameters, mixed notation
-- ---------------------------------------------------------------------
SELECT app.gst_amount(amount => 2500),
       app.gst_amount(rate => 0.12, amount => 2500),
       app.gst_amount(2500, rate => 0.28);

-- ---------------------------------------------------------------------
-- [Q16.04] SQL-standard function body (parsed & dependency-tracked at creation)
-- Keywords: BEGIN ATOMIC, RETURN
-- Business question: Is a coupon currently usable? (PG14+)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.coupon_is_live(p_code text)
RETURNS boolean
LANGUAGE sql
STABLE
BEGIN ATOMIC
    SELECT EXISTS (SELECT 1 FROM sales.coupons
                   WHERE code = p_code AND is_active AND valid_during @> now());
END;
SELECT app.coupon_is_live('WELCOME10') AS welcome10, app.coupon_is_live('OLDCODE') AS oldcode;

-- ---------------------------------------------------------------------
-- [Q16.05] Functions returning several columns
-- Keywords: OUT parameters, RETURNS record
-- Business question: Quick stats for one user.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.user_stats(p_user_id bigint, OUT orders bigint, OUT lifetime_value numeric, OUT last_order timestamptz)
LANGUAGE sql STABLE
AS $$
    SELECT count(*), COALESCE(sum(grand_total), 0), max(placed_at)
    FROM sales.orders WHERE user_id = p_user_id AND status <> 'cancelled'
$$;
SELECT * FROM app.user_stats(42);
SELECT u.user_id, (app.user_stats(u.user_id)).lifetime_value FROM core.users u WHERE u.user_id <= 3;

-- ---------------------------------------------------------------------
-- [Q16.06] Table functions: return a set of rows
-- Keywords: RETURNS TABLE, RETURNS SETOF, function in FROM, LATERAL call
-- Business question: Seller dashboard: top N products of a seller.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.seller_top_products(p_seller_id bigint, p_limit int DEFAULT 5)
RETURNS TABLE (product_id bigint, name text, units bigint, revenue numeric)
LANGUAGE sql STABLE
AS $$
    SELECT p.product_id, p.name, sum(oi.quantity), sum(oi.line_total)
    FROM sales.order_items oi
    JOIN catalog.product_variants v USING (variant_id)
    JOIN catalog.products p USING (product_id)
    WHERE oi.seller_id = p_seller_id
    GROUP BY p.product_id, p.name
    ORDER BY 4 DESC
    LIMIT p_limit
$$;
SELECT * FROM app.seller_top_products(3, 3);
CREATE OR REPLACE FUNCTION app.open_orders_of(p_user_id bigint)
RETURNS SETOF sales.orders                                   -- returns whole rows of an existing table type
LANGUAGE sql STABLE
AS $$ SELECT * FROM sales.orders WHERE user_id = p_user_id AND status IN ('pending', 'paid', 'packed', 'shipped') $$;
SELECT s.store_name, t.name, t.revenue
FROM core.sellers s
CROSS JOIN LATERAL app.seller_top_products(s.seller_id, 1) t
WHERE s.seller_id <= 3;

-- =====================================================================
-- SECTION: PL/pgSQL
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q16.07] Variables, IF/ELSIF, %TYPE, SELECT INTO, RAISE
-- Keywords: LANGUAGE plpgsql, DECLARE, %TYPE, SELECT … INTO, IF … ELSIF … ELSE, RETURN, RAISE EXCEPTION
-- Business question: Calculate the discount a coupon gives for a cart amount, with all business rules.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.coupon_discount(p_code text, p_cart_amount numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    c        sales.coupons%ROWTYPE;              -- a whole row
    discount sales.coupons.discount_value%TYPE;  -- same type as a column
BEGIN
    SELECT * INTO c FROM sales.coupons WHERE code = p_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown coupon %', p_code USING ERRCODE = 'no_data_found', HINT = 'Check the code spelling';
    ELSIF NOT c.is_active OR NOT (c.valid_during @> now()) THEN
        RETURN 0;
    ELSIF p_cart_amount < c.min_order_amount THEN
        RAISE NOTICE 'Cart % below minimum %', p_cart_amount, c.min_order_amount;
        RETURN 0;
    END IF;

    IF c.discount_type = 'percent' THEN
        discount := round(p_cart_amount * c.discount_value / 100, 2);
        IF c.max_discount IS NOT NULL THEN
            discount := least(discount, c.max_discount);
        END IF;
    ELSE
        discount := c.discount_value;
    END IF;
    RETURN least(discount, p_cart_amount);
END;
$$;
SELECT app.coupon_discount('WELCOME10', 1500) AS ten_pct, app.coupon_discount('WELCOME10', 5000) AS capped,
       app.coupon_discount('PRIME15', 100) AS below_min;

-- ---------------------------------------------------------------------
-- [Q16.08] Catch errors inside PL/pgSQL
-- Keywords: EXCEPTION WHEN, SQLSTATE, SQLERRM, GET STACKED DIAGNOSTICS
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.safe_coupon_discount(p_code text, p_cart_amount numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_state text; v_msg text; v_hint text;
BEGIN
    RETURN app.coupon_discount(p_code, p_cart_amount);
EXCEPTION
    WHEN no_data_found THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_hint = PG_EXCEPTION_HINT;
        RAISE WARNING 'Ignoring coupon: % (SQLSTATE %, hint: %)', v_msg, v_state, v_hint;
        RETURN 0;
END;
$$;
SELECT app.safe_coupon_discount('NOPE', 999) AS discount;

-- ---------------------------------------------------------------------
-- [Q16.09] Loops: FOR over a query, WHILE, LOOP/EXIT/CONTINUE, FOREACH over an array
-- Keywords: FOR … IN SELECT LOOP, WHILE, LOOP, EXIT WHEN, CONTINUE WHEN, FOREACH … IN ARRAY
-- Business question: Build a shipping-rate table: weight slabs × zones.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.shipping_rate_card(p_zones text[])
RETURNS TABLE (zone text, max_kg int, fee numeric)
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    z     text;
    kg    int;
    base  numeric;
BEGIN
    FOREACH z IN ARRAY p_zones LOOP
        base := CASE z WHEN 'metro' THEN 40 WHEN 'tier2' THEN 60 ELSE 90 END;
        kg := 0;
        LOOP
            kg := kg + 1;
            EXIT WHEN kg > 10;                 -- leave the loop
            CONTINUE WHEN kg % 2 = 1;          -- only even slabs
            zone := z; max_kg := kg; fee := base + (kg - 1) * 15;
            RETURN NEXT;                       -- append one row to the result
        END LOOP;
    END LOOP;
END;
$$;
SELECT * FROM app.shipping_rate_card(ARRAY['metro', 'remote']) LIMIT 6;

CREATE OR REPLACE FUNCTION app.restock_report()
RETURNS SETOF text
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    r record;
    n int := 0;
BEGIN
    FOR r IN SELECT w.code, count(*) AS low
             FROM logistics.inventory i JOIN logistics.warehouses w USING (warehouse_id)
             WHERE i.quantity_on_hand - i.quantity_reserved < i.reorder_level
             GROUP BY w.code ORDER BY low DESC
    LOOP
        n := n + 1;
        RETURN NEXT format('%s. %s needs %s restocks', n, r.code, r.low);
    END LOOP;
    WHILE n < 10 LOOP
        n := n + 1;                              -- WHILE demo: pad the report to 10 lines
        RETURN NEXT format('%s. -', n);
    END LOOP;
END;
$$;
SELECT * FROM app.restock_report();

-- ---------------------------------------------------------------------
-- [Q16.10] Return a whole query result from PL/pgSQL
-- Keywords: RETURN QUERY, RETURN QUERY EXECUTE
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.orders_by_status(p_status sales.order_status, p_limit int DEFAULT 3)
RETURNS TABLE (order_number text, placed_at timestamptz)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
        SELECT o.order_number, o.placed_at FROM sales.orders o
        WHERE o.status = p_status ORDER BY o.placed_at DESC LIMIT p_limit;
END;
$$;
SELECT * FROM app.orders_by_status('shipped');

-- ---------------------------------------------------------------------
-- [Q16.11] Dynamic SQL — safely
-- Keywords: EXECUTE format() USING, %I, %L, quote_ident(), SQL injection
-- Business question: Count rows of any table in a whitelisted schema (admin tool).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.count_rows(p_schema text, p_table text, p_since timestamptz DEFAULT NULL, p_ts_column text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    result bigint;
BEGIN
    IF p_schema NOT IN ('core', 'catalog', 'logistics', 'sales') THEN
        RAISE EXCEPTION 'schema % not allowed', p_schema;
    END IF;
    IF p_since IS NULL THEN
        EXECUTE format('SELECT count(*) FROM %I.%I', p_schema, p_table) INTO result;           -- %I quotes identifiers
    ELSE
        EXECUTE format('SELECT count(*) FROM %I.%I WHERE %I >= $1', p_schema, p_table, p_ts_column)
            INTO result USING p_since;                                                     -- values via USING, never concatenated
    END IF;
    RETURN result;
END;
$$;
SELECT app.count_rows('sales', 'orders') AS all_orders,
       app.count_rows('sales', 'orders', now() - interval '7 days', 'placed_at') AS last_week;

-- ---------------------------------------------------------------------
-- [Q16.12] Row counts and FOUND after DML
-- Keywords: GET DIAGNOSTICS … ROW_COUNT, FOUND, PERFORM
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.expire_old_carts(p_days int)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
    n int;
BEGIN
    PERFORM 1 FROM sales.carts LIMIT 1;           -- PERFORM = run a query, discard result
    IF NOT FOUND THEN RETURN 0; END IF;
    DELETE FROM sales.cart_items ci USING sales.carts c
    WHERE c.cart_id = ci.cart_id AND c.updated_at < now() - make_interval(days => p_days);
    GET DIAGNOSTICS n = ROW_COUNT;
    RAISE NOTICE 'Removed % cart items', n;
    RETURN n;
END;
$$;
BEGIN;
SELECT app.expire_old_carts(60) AS removed_items;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q16.13] Cursors: process a big result in chunks
-- Keywords: refcursor, OPEN … FOR, FETCH, CLOSE, cursor FOR loop
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sample_big_orders(p_take int)
RETURNS SETOF text
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    cur CURSOR FOR SELECT order_number, grand_total FROM sales.orders ORDER BY grand_total DESC;
    rec record;
BEGIN
    OPEN cur;
    FOR i IN 1 .. p_take LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        RETURN NEXT rec.order_number || ' = ₹' || rec.grand_total;
    END LOOP;
    CLOSE cur;
END;
$$;
SELECT * FROM app.sample_big_orders(3);

-- =====================================================================
-- SECTION: Advanced signatures
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q16.14] Variable number of arguments
-- Keywords: VARIADIC
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.first_non_empty(VARIADIC p_values text[])
RETURNS text LANGUAGE sql IMMUTABLE
AS $$ SELECT v FROM unnest(p_values) v WHERE nullif(trim(v), '') IS NOT NULL LIMIT 1 $$;
SELECT app.first_non_empty('', '  ', 'Bengaluru', 'Mumbai') AS a,
       app.first_non_empty(VARIADIC ARRAY[NULL, 'x']) AS b;

-- ---------------------------------------------------------------------
-- [Q16.15] One function for many types
-- Keywords: anyelement, anyarray, anycompatible, polymorphic functions
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.clamp(val anycompatible, lo anycompatible, hi anycompatible)
RETURNS anycompatible LANGUAGE sql IMMUTABLE
AS $$ SELECT greatest(lo, least(hi, val)) $$;
CREATE OR REPLACE FUNCTION app.last_element(arr anyarray)
RETURNS anyelement LANGUAGE sql IMMUTABLE
AS $$ SELECT arr[array_upper(arr, 1)] $$;
SELECT app.clamp(150, 0, 100) AS int_clamp, app.clamp(2.5, 1, 2) AS numeric_clamp,
       app.clamp(now(), now() - interval '1 day', now() + interval '1 day') = now() AS ts_clamp,
       app.last_element(ARRAY['a', 'b', 'c']) AS last_text;

-- ---------------------------------------------------------------------
-- [Q16.16] Overloading: same name, different argument types
-- Keywords: function overloading, pg_get_function_identity_arguments()
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.describe(p bigint) RETURNS text LANGUAGE sql STABLE
AS $$ SELECT 'product: ' || name FROM catalog.products WHERE product_id = p $$;
CREATE OR REPLACE FUNCTION app.describe(p text) RETURNS text LANGUAGE sql STABLE
AS $$ SELECT 'coupon: ' || description FROM sales.coupons WHERE code = p $$;
SELECT app.describe(1::bigint), app.describe('WELCOME10'::text);
SELECT proname, pg_get_function_identity_arguments(oid) AS args
FROM pg_proc WHERE pronamespace = 'app'::regnamespace AND proname = 'describe';

-- =====================================================================
-- SECTION: Procedures & anonymous blocks
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q16.17] Procedures can COMMIT inside — perfect for batch jobs
-- Keywords: CREATE PROCEDURE, CALL, COMMIT inside procedure, INOUT
-- Business question: Archive old read notifications in batches, committing each batch.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app.notifications_archive (LIKE core.notifications);
CREATE OR REPLACE PROCEDURE app.archive_notifications(p_older_than interval, p_batch int, INOUT moved int DEFAULT 0)
LANGUAGE plpgsql
AS $$
DECLARE
    n int;
BEGIN
    LOOP
        WITH batch AS (
            DELETE FROM core.notifications
            WHERE notification_id IN (SELECT notification_id FROM core.notifications
                                      WHERE read_at IS NOT NULL AND sent_at < now() - p_older_than
                                      LIMIT p_batch)
            RETURNING *)
        INSERT INTO app.notifications_archive SELECT * FROM batch;
        GET DIAGNOSTICS n = ROW_COUNT;
        moved := moved + n;
        EXIT WHEN n = 0;
        COMMIT;                                  -- release locks / WAL per batch
    END LOOP;
END;
$$;
CALL app.archive_notifications(interval '540 days', 200);          -- archives a few hundred old rows
-- put them back so the seed data stays intact for other chapters
INSERT INTO core.notifications OVERRIDING SYSTEM VALUE SELECT * FROM app.notifications_archive;
TRUNCATE app.notifications_archive;

-- ---------------------------------------------------------------------
-- [Q16.18] A business transaction as a procedure
-- Keywords: procedure with OUT parameter (PG14+), RAISE … USING ERRCODE, transaction control by caller
-- Business question: place_order(user, variant, qty) → order id, with stock reservation.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE app.place_order(p_user_id bigint, p_variant_id bigint, p_qty int, OUT new_order_id bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_wh smallint;
BEGIN
    UPDATE logistics.inventory SET quantity_reserved = quantity_reserved + p_qty
    WHERE (variant_id, warehouse_id) = (SELECT variant_id, warehouse_id FROM logistics.inventory
                                        WHERE variant_id = p_variant_id AND quantity_on_hand - quantity_reserved >= p_qty
                                        ORDER BY quantity_on_hand - quantity_reserved DESC LIMIT 1 FOR UPDATE)
    RETURNING warehouse_id INTO v_wh;
    IF v_wh IS NULL THEN
        RAISE EXCEPTION 'Variant % out of stock', p_variant_id USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO sales.orders (order_number, user_id, shipping_address_id)
    SELECT 'SS-' || to_char(now(), 'YYYYMMDD') || '-P' || nextval(pg_get_serial_sequence('sales.orders', 'order_id')),
           p_user_id, (SELECT address_id FROM core.addresses WHERE user_id = p_user_id AND is_default)
    RETURNING order_id INTO new_order_id;

    INSERT INTO sales.order_items (order_id, variant_id, seller_id, quantity, unit_price)
    SELECT new_order_id, v.variant_id, p.seller_id, p_qty, app.variant_price(v.variant_id)
    FROM catalog.product_variants v JOIN catalog.products p USING (product_id)
    WHERE v.variant_id = p_variant_id;

    UPDATE sales.orders SET subtotal = (SELECT sum(line_total) FROM sales.order_items WHERE order_id = new_order_id)
    WHERE order_id = new_order_id;
END;
$$;
BEGIN;
CALL app.place_order(21, 9, 1, NULL);
SELECT order_number, status, subtotal, grand_total FROM sales.orders ORDER BY order_id DESC LIMIT 1;
ROLLBACK;

-- ---------------------------------------------------------------------
-- [Q16.19] Anonymous code blocks
-- Keywords: DO, LANGUAGE plpgsql (default), RAISE INFO
-- Business question: A one-off maintenance script — report table sizes per schema.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    s text;
BEGIN
    FOR s IN SELECT unnest(ARRAY['core', 'catalog', 'logistics', 'sales']) LOOP
        RAISE INFO 'schema % uses %', s,
            (SELECT pg_size_pretty(sum(pg_total_relation_size(c.oid))) FROM pg_class c
             WHERE c.relnamespace = s::regnamespace AND c.relkind = 'r');
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- [Q16.20] SECURITY DEFINER: run with the owner's rights (lock down search_path!)
-- Keywords: SECURITY DEFINER, SET search_path, REVOKE EXECUTE … FROM PUBLIC
-- Business question: Let support staff look up a masked phone number without table access.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.masked_phone(p_user_id bigint)
RETURNS text
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp                    -- prevents search_path hijacking
AS $$ SELECT left(phone, 3) || repeat('*', length(phone) - 6) || right(phone, 3) FROM core.users WHERE user_id = p_user_id $$;
REVOKE EXECUTE ON FUNCTION app.masked_phone(bigint) FROM PUBLIC;
SELECT app.masked_phone(1);

-- ---------------------------------------------------------------------
-- [Q16.21] Inspect and drop functions
-- Keywords: pg_proc, pg_get_functiondef(), DROP FUNCTION (with signature), DROP PROCEDURE
-- ---------------------------------------------------------------------
SELECT p.proname, p.prokind, pg_get_function_identity_arguments(p.oid) AS args, l.lanname
FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
WHERE p.pronamespace = 'app'::regnamespace
ORDER BY p.proname
LIMIT 10;
SELECT pg_get_functiondef('app.gst_amount(numeric, numeric)'::regprocedure);
CREATE OR REPLACE FUNCTION app.tmp_demo() RETURNS int LANGUAGE sql AS 'SELECT 1';
DROP FUNCTION IF EXISTS app.tmp_demo();
