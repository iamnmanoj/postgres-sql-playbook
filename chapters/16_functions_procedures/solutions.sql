-- =====================================================================
--  Chapter 16 · Solutions — functions, procedures & PL/pgSQL
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS app;

-- [E16.01] IMMUTABLE SQL function
-- Keywords: CREATE FUNCTION, IMMUTABLE
CREATE OR REPLACE FUNCTION app.ex16_with_gst(price numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$ SELECT round(price * 1.18, 2) $$;
SELECT name, base_price, app.ex16_with_gst(base_price) AS with_gst FROM catalog.products LIMIT 3;

-- [E16.02] STABLE lookup function
-- Keywords: STABLE, avg()
CREATE OR REPLACE FUNCTION app.ex16_product_rating(p_product_id bigint)
RETURNS numeric LANGUAGE sql STABLE
AS $$ SELECT round(avg(rating), 2) FROM catalog.reviews WHERE product_id = p_product_id $$;
SELECT app.ex16_product_rating(1) AS rated, app.ex16_product_rating(-1) AS none;

-- [E16.03] Gap-free daily series
-- Keywords: RETURNS TABLE, generate_series(), LEFT JOIN
CREATE OR REPLACE FUNCTION app.ex16_orders_between(p_from date, p_to date)
RETURNS TABLE (day date, orders bigint, gmv numeric)
LANGUAGE sql STABLE
AS $$
    SELECT d::date, count(o.order_id), COALESCE(sum(o.grand_total), 0)
    FROM generate_series(p_from, p_to, interval '1 day') d
    LEFT JOIN sales.orders o ON o.placed_at >= d AND o.placed_at < d + interval '1 day'
    GROUP BY d
    ORDER BY d
$$;
SELECT * FROM app.ex16_orders_between(current_date - 6, current_date);

-- [E16.04] Loyalty tier with error handling
-- Keywords: PL/pgSQL, IF NOT FOUND, RAISE EXCEPTION … USING HINT, CASE
CREATE OR REPLACE FUNCTION app.ex16_loyalty_tier(p_user_id bigint)
RETURNS text LANGUAGE plpgsql STABLE
AS $$
DECLARE
    ltv numeric;
BEGIN
    PERFORM 1 FROM core.users WHERE user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found', p_user_id USING HINT = 'Pass an existing core.users.user_id';
    END IF;
    SELECT COALESCE(sum(grand_total), 0) INTO ltv
    FROM sales.orders WHERE user_id = p_user_id AND status = 'delivered';
    RETURN CASE WHEN ltv >= 1000000 THEN 'platinum'
                WHEN ltv >= 300000 THEN 'gold'
                WHEN ltv >= 50000 THEN 'silver'
                ELSE 'bronze' END;
END;
$$;
SELECT user_id, app.ex16_loyalty_tier(user_id) FROM core.users WHERE user_id IN (1, 100, 4999);

-- [E16.05] Re-pricing procedure
-- Keywords: CREATE PROCEDURE, data-modifying CTE, GET DIAGNOSTICS, RAISE NOTICE
CREATE OR REPLACE PROCEDURE app.ex16_reprice_brand(p_brand text, p_pct numeric)
LANGUAGE plpgsql
AS $$
DECLARE
    n int;
BEGIN
    WITH changed AS (
        UPDATE catalog.products p
        SET base_price = round(p.base_price * (1 + p_pct / 100), 2), updated_at = now()
        FROM catalog.brands b
        WHERE b.brand_id = p.brand_id AND b.name = p_brand
        RETURNING p.product_id, p.base_price AS new_price, round(p.base_price / (1 + p_pct / 100), 2) AS old_price
    )
    INSERT INTO catalog.price_history (product_id, old_price, new_price)
    SELECT product_id, old_price, new_price FROM changed;
    GET DIAGNOSTICS n = ROW_COUNT;
    RAISE NOTICE 'Repriced % products of %', n, p_brand;
END;
$$;
BEGIN;
CALL app.ex16_reprice_brand('Voltix', 5);
ROLLBACK;

-- [E16.06] Dynamic table stats
-- Keywords: EXECUTE format('%I'), RETURNS TABLE, pg_total_relation_size()
CREATE OR REPLACE FUNCTION app.ex16_table_stats(p_schema text, p_table text)
RETURNS TABLE (row_count bigint, total_size text)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    IF p_schema NOT IN ('catalog', 'sales') THEN
        RAISE EXCEPTION 'schema % not allowed', p_schema;
    END IF;
    RETURN QUERY EXECUTE format(
        'SELECT count(*), pg_size_pretty(pg_total_relation_size(%L)) FROM %I.%I',
        p_schema || '.' || p_table, p_schema, p_table);
END;
$$;
SELECT * FROM app.ex16_table_stats('sales', 'orders');
