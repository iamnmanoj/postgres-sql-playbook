-- =====================================================================
--  ShopSphere — a multi-seller e-commerce marketplace
--  Chapter 01 · The application schema (run by scripts/reset.sh)
--
--  Think "Amazon/Flipkart-lite": buyers browse a category tree, add
--  product variants to a cart, apply coupons, place orders, pay, get
--  shipments from warehouses, return items, and write reviews.
--  Sellers list products and receive payouts.
--
--  Schemas (namespaces) group related tables:
--    core       users, roles, addresses, sellers, payouts, notifications
--    catalog    categories, brands, products, variants, images, prices, reviews
--    logistics  warehouses, inventory, stock movements, shipments
--    sales      carts, wishlists, coupons, orders, payments, refunds, returns
--    audit      change log written by triggers
--    analytics  click-stream events (partitioned table)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Extensions: add-on features shipped with PostgreSQL
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS citext;              -- case-insensitive text type
CREATE EXTENSION IF NOT EXISTS pg_trgm;             -- trigram fuzzy matching (ch13, ch14)
CREATE EXTENSION IF NOT EXISTS btree_gist;          -- "=" inside GiST EXCLUDE constraints
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;  -- query statistics (ch14)

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS catalog;
CREATE SCHEMA IF NOT EXISTS logistics;
CREATE SCHEMA IF NOT EXISTS sales;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS analytics;

COMMENT ON SCHEMA core      IS 'People: users, roles, addresses, sellers, payouts';
COMMENT ON SCHEMA catalog   IS 'What we sell: categories, brands, products, variants, reviews';
COMMENT ON SCHEMA logistics IS 'Where stock lives and how it moves: warehouses, inventory, shipments';
COMMENT ON SCHEMA sales     IS 'Money flow: carts, coupons, orders, payments, refunds, returns';
COMMENT ON SCHEMA audit     IS 'Change history captured by triggers';
COMMENT ON SCHEMA analytics IS 'High-volume click-stream data';

-- Let unqualified names resolve across our schemas (try: SHOW search_path;)
DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET search_path = core, catalog, logistics, sales, audit, analytics, public',
                   current_database());
END $$;
SET search_path = core, catalog, logistics, sales, audit, analytics, public;

-- ---------------------------------------------------------------------
-- ENUM types: a fixed, ordered list of allowed labels
-- ---------------------------------------------------------------------
CREATE TYPE core.user_status        AS ENUM ('active', 'suspended', 'deleted');
CREATE TYPE sales.order_status      AS ENUM ('pending', 'paid', 'packed', 'shipped', 'delivered', 'cancelled', 'refunded');
CREATE TYPE sales.payment_method    AS ENUM ('card', 'upi', 'wallet', 'netbanking', 'cod');
CREATE TYPE sales.payment_status    AS ENUM ('initiated', 'authorized', 'captured', 'failed', 'refunded');
CREATE TYPE sales.discount_type     AS ENUM ('percent', 'fixed');
CREATE TYPE logistics.shipment_status AS ENUM ('label_created', 'in_transit', 'out_for_delivery', 'delivered', 'returned', 'lost');

-- ---------------------------------------------------------------------
-- DOMAINs: a base type + reusable constraints
-- ---------------------------------------------------------------------
CREATE DOMAIN core.email AS citext
    CHECK (VALUE ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');
CREATE DOMAIN core.phone AS text
    CHECK (VALUE ~ '^\+[1-9][0-9]{7,14}$');               -- E.164 format
CREATE DOMAIN core.money_amount AS numeric(12, 2)
    CHECK (VALUE >= 0);
CREATE DOMAIN core.rating AS smallint
    CHECK (VALUE BETWEEN 1 AND 5);

-- =====================================================================
-- CORE
-- =====================================================================
CREATE TABLE core.users (
    user_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id      uuid        NOT NULL DEFAULT gen_random_uuid() UNIQUE,  -- safe to expose in URLs
    email          core.email  NOT NULL UNIQUE,
    full_name      text        NOT NULL CHECK (length(trim(full_name)) > 0),
    phone          core.phone,
    date_of_birth  date        CHECK (date_of_birth > DATE '1900-01-01'),
    status         core.user_status NOT NULL DEFAULT 'active',
    is_prime       boolean     NOT NULL DEFAULT false,
    referred_by    bigint      REFERENCES core.users (user_id) ON DELETE SET NULL,  -- self-reference
    preferences    jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    last_login_at  timestamptz,
    CONSTRAINT users_not_self_referred CHECK (referred_by IS DISTINCT FROM user_id)
);
COMMENT ON TABLE  core.users IS 'Every person with an account: buyers, sellers, admins';
COMMENT ON COLUMN core.users.public_id IS 'Random UUID shown to clients instead of the sequential user_id';

CREATE TABLE core.roles (
    role_id  smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name     text NOT NULL UNIQUE
);

CREATE TABLE core.user_roles (                      -- many-to-many bridge table
    user_id    bigint   NOT NULL REFERENCES core.users (user_id) ON DELETE CASCADE,
    role_id    smallint NOT NULL REFERENCES core.roles (role_id),
    granted_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id)                  -- composite primary key
);

CREATE TABLE core.addresses (
    address_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      bigint  NOT NULL REFERENCES core.users (user_id) ON DELETE CASCADE,
    label        text    NOT NULL DEFAULT 'home' CHECK (label IN ('home', 'work', 'other')),
    line1        text    NOT NULL,
    line2        text,
    city         text    NOT NULL,
    state        text    NOT NULL,
    postal_code  text    NOT NULL CHECK (postal_code ~ '^[0-9]{6}$'),
    country_code char(2) NOT NULL DEFAULT 'IN',
    is_default   boolean NOT NULL DEFAULT false,
    created_at   timestamptz NOT NULL DEFAULT now()
);
-- Partial UNIQUE index: at most ONE default address per user
CREATE UNIQUE INDEX addresses_one_default_per_user
    ON core.addresses (user_id) WHERE is_default;
CREATE INDEX addresses_user_id_idx ON core.addresses (user_id);

CREATE TABLE core.sellers (
    seller_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    owner_user_id   bigint NOT NULL UNIQUE REFERENCES core.users (user_id),  -- 1:1 with a user
    store_name      text   NOT NULL UNIQUE,
    slug            text   NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9-]+$'),
    gstin           text   UNIQUE,
    commission_rate numeric(5, 4) NOT NULL DEFAULT 0.1000 CHECK (commission_rate BETWEEN 0 AND 0.5),
    is_verified     boolean NOT NULL DEFAULT false,
    rating_avg      numeric(3, 2) CHECK (rating_avg BETWEEN 1 AND 5),
    settings        jsonb   NOT NULL DEFAULT '{}'::jsonb,
    joined_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE core.seller_payouts (
    payout_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id   bigint NOT NULL REFERENCES core.sellers (seller_id),
    period      daterange NOT NULL,                       -- e.g. [2025-01-01,2025-02-01)
    gross_sales core.money_amount NOT NULL,
    commission  core.money_amount NOT NULL,
    net_amount  numeric(12, 2) GENERATED ALWAYS AS (gross_sales - commission) STORED,
    status      text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'paid', 'on_hold')),
    paid_at     timestamptz,
    -- EXCLUDE constraint: a seller can never have two payouts with overlapping periods
    CONSTRAINT seller_payouts_no_overlap EXCLUDE USING gist (seller_id WITH =, period WITH &&)
);

CREATE TABLE core.notifications (
    notification_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id   bigint NOT NULL REFERENCES core.users (user_id) ON DELETE CASCADE,
    channel   text   NOT NULL CHECK (channel IN ('email', 'sms', 'push')),
    template  text   NOT NULL,
    payload   jsonb  NOT NULL DEFAULT '{}'::jsonb,
    sent_at   timestamptz NOT NULL DEFAULT now(),
    read_at   timestamptz
);

-- =====================================================================
-- CATALOG
-- =====================================================================
CREATE TABLE catalog.categories (
    category_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_id   int REFERENCES catalog.categories (category_id),   -- tree: NULL = root
    name        text NOT NULL,
    slug        text NOT NULL UNIQUE,
    sort_order  smallint NOT NULL DEFAULT 0,
    UNIQUE (parent_id, name)
);

CREATE TABLE catalog.brands (
    brand_id     int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         text NOT NULL UNIQUE,
    country_code char(2),
    founded_year smallint CHECK (founded_year BETWEEN 1800 AND 2100)
);

CREATE TABLE catalog.products (
    product_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id     bigint NOT NULL REFERENCES core.sellers (seller_id),
    category_id   int    NOT NULL REFERENCES catalog.categories (category_id),
    brand_id      int    REFERENCES catalog.brands (brand_id),
    sku           text   NOT NULL UNIQUE,
    name          text   NOT NULL,
    description   text,
    base_price    core.money_amount NOT NULL,
    currency      char(3) NOT NULL DEFAULT 'INR',
    attributes    jsonb  NOT NULL DEFAULT '{}'::jsonb,   -- flexible spec sheet
    tags          text[] NOT NULL DEFAULT '{}',          -- array column
    weight_grams  int    CHECK (weight_grams > 0),
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    -- Generated column: kept in sync automatically, used by full-text search
    search_vector tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(description, '')), 'B')
    ) STORED
);
CREATE INDEX products_seller_id_idx   ON catalog.products (seller_id);
CREATE INDEX products_category_id_idx ON catalog.products (category_id);

CREATE TABLE catalog.product_variants (
    variant_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id  bigint NOT NULL REFERENCES catalog.products (product_id) ON DELETE CASCADE,
    sku         text   NOT NULL UNIQUE,
    options     jsonb  NOT NULL DEFAULT '{}'::jsonb,     -- {"color":"red","size":"M"}
    price_delta numeric(12, 2) NOT NULL DEFAULT 0,       -- added to products.base_price
    is_active   boolean NOT NULL DEFAULT true
);
CREATE INDEX product_variants_product_id_idx ON catalog.product_variants (product_id);

CREATE TABLE catalog.product_images (
    image_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id bigint NOT NULL REFERENCES catalog.products (product_id) ON DELETE CASCADE,
    url        text   NOT NULL,
    position   smallint NOT NULL DEFAULT 1 CHECK (position > 0),
    alt_text   text,
    UNIQUE (product_id, position)
);

CREATE TABLE catalog.price_history (
    price_history_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id bigint NOT NULL REFERENCES catalog.products (product_id) ON DELETE CASCADE,
    old_price  numeric(12, 2) NOT NULL,
    new_price  numeric(12, 2) NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX price_history_product_idx ON catalog.price_history (product_id, changed_at);

-- =====================================================================
-- LOGISTICS
-- =====================================================================
CREATE TABLE logistics.warehouses (
    warehouse_id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code         text NOT NULL UNIQUE,
    city         text NOT NULL,
    state        text NOT NULL,
    capacity     int  NOT NULL CHECK (capacity > 0),
    opened_on    date NOT NULL
);

CREATE TABLE logistics.inventory (
    variant_id        bigint   NOT NULL REFERENCES catalog.product_variants (variant_id) ON DELETE CASCADE,
    warehouse_id      smallint NOT NULL REFERENCES logistics.warehouses (warehouse_id),
    quantity_on_hand  int NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    quantity_reserved int NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    reorder_level     int NOT NULL DEFAULT 10,
    updated_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (variant_id, warehouse_id),
    CONSTRAINT inventory_reserved_le_on_hand CHECK (quantity_reserved <= quantity_on_hand)
);

CREATE TABLE logistics.inventory_movements (
    movement_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    variant_id   bigint   NOT NULL,
    warehouse_id smallint NOT NULL,
    change       int  NOT NULL CHECK (change <> 0),          -- +in / -out
    reason       text NOT NULL CHECK (reason IN ('purchase', 'sale', 'return', 'adjustment', 'transfer')),
    reference_id bigint,                                     -- e.g. order_id
    created_at   timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (variant_id, warehouse_id)                   -- composite foreign key
        REFERENCES logistics.inventory (variant_id, warehouse_id) ON DELETE CASCADE
);
CREATE INDEX inventory_movements_variant_idx ON logistics.inventory_movements (variant_id, warehouse_id);

-- =====================================================================
-- SALES
-- =====================================================================
CREATE TABLE sales.carts (
    cart_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    bigint NOT NULL UNIQUE REFERENCES core.users (user_id) ON DELETE CASCADE,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sales.cart_items (
    cart_id    bigint NOT NULL REFERENCES sales.carts (cart_id) ON DELETE CASCADE,
    variant_id bigint NOT NULL REFERENCES catalog.product_variants (variant_id),
    quantity   int    NOT NULL CHECK (quantity BETWEEN 1 AND 10),
    added_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (cart_id, variant_id)
);

CREATE TABLE sales.wishlists (
    user_id    bigint NOT NULL REFERENCES core.users (user_id) ON DELETE CASCADE,
    product_id bigint NOT NULL REFERENCES catalog.products (product_id) ON DELETE CASCADE,
    added_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, product_id)
);

CREATE TABLE sales.coupons (
    coupon_id        int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code             citext NOT NULL UNIQUE,                 -- 'save10' = 'SAVE10'
    description      text,
    discount_type    sales.discount_type NOT NULL,
    discount_value   numeric(10, 2) NOT NULL CHECK (discount_value > 0),
    max_discount     numeric(10, 2),
    min_order_amount numeric(10, 2) NOT NULL DEFAULT 0,
    valid_during     tstzrange NOT NULL,                     -- range type
    usage_limit      int,                                    -- NULL = unlimited
    per_user_limit   int NOT NULL DEFAULT 1,
    seller_id        bigint REFERENCES core.sellers (seller_id),  -- NULL = platform-wide
    is_active        boolean NOT NULL DEFAULT true,
    CONSTRAINT coupons_percent_max_100 CHECK (discount_type <> 'percent' OR discount_value <= 100)
);

CREATE TABLE sales.orders (
    order_id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_number        text   NOT NULL UNIQUE,
    user_id             bigint NOT NULL REFERENCES core.users (user_id),
    shipping_address_id bigint REFERENCES core.addresses (address_id),
    status              sales.order_status NOT NULL DEFAULT 'pending',
    coupon_id           int REFERENCES sales.coupons (coupon_id),
    subtotal            core.money_amount NOT NULL DEFAULT 0,
    discount_total      core.money_amount NOT NULL DEFAULT 0,
    shipping_fee        core.money_amount NOT NULL DEFAULT 0,
    tax_total           core.money_amount NOT NULL DEFAULT 0,
    grand_total         numeric(12, 2) GENERATED ALWAYS AS
                            (subtotal - discount_total + shipping_fee + tax_total) STORED,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {"channel":"app","device":"android"}
    notes               text,
    placed_at           timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX orders_user_id_idx   ON sales.orders (user_id);
CREATE INDEX orders_placed_at_idx ON sales.orders (placed_at);

CREATE TABLE sales.order_items (
    order_item_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      bigint NOT NULL REFERENCES sales.orders (order_id) ON DELETE CASCADE,
    variant_id    bigint NOT NULL REFERENCES catalog.product_variants (variant_id),
    seller_id     bigint NOT NULL REFERENCES core.sellers (seller_id),   -- denormalised for seller reports & RLS
    quantity      int    NOT NULL CHECK (quantity > 0),
    unit_price    core.money_amount NOT NULL,
    discount      numeric(12, 2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
    line_total    numeric(12, 2) GENERATED ALWAYS AS (quantity * unit_price - discount) STORED,
    UNIQUE (order_id, variant_id)
);
CREATE INDEX order_items_order_id_idx   ON sales.order_items (order_id);
CREATE INDEX order_items_variant_id_idx ON sales.order_items (variant_id);
CREATE INDEX order_items_seller_id_idx  ON sales.order_items (seller_id);

CREATE TABLE sales.order_status_history (
    history_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    bigint NOT NULL REFERENCES sales.orders (order_id) ON DELETE CASCADE,
    from_status sales.order_status,
    to_status   sales.order_status NOT NULL,
    changed_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX order_status_history_order_idx ON sales.order_status_history (order_id);

CREATE TABLE sales.coupon_redemptions (
    redemption_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    coupon_id       int    NOT NULL REFERENCES sales.coupons (coupon_id),
    user_id         bigint NOT NULL REFERENCES core.users (user_id),
    order_id        bigint NOT NULL UNIQUE REFERENCES sales.orders (order_id) ON DELETE CASCADE,
    discount_amount core.money_amount NOT NULL,
    redeemed_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sales.payments (
    payment_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id         bigint NOT NULL REFERENCES sales.orders (order_id) ON DELETE CASCADE,
    method           sales.payment_method NOT NULL,
    status           sales.payment_status NOT NULL DEFAULT 'initiated',
    amount           core.money_amount NOT NULL,
    provider_ref     text UNIQUE,
    gateway_response jsonb,
    created_at       timestamptz NOT NULL DEFAULT now(),
    captured_at      timestamptz
);
CREATE INDEX payments_order_id_idx ON sales.payments (order_id);

CREATE TABLE sales.refunds (
    refund_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_id   bigint NOT NULL REFERENCES sales.payments (payment_id),
    amount       core.money_amount NOT NULL CHECK (amount > 0),
    reason       text NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz
);

-- =====================================================================
-- LOGISTICS (continued): shipments depend on orders
-- =====================================================================
CREATE TABLE logistics.shipments (
    shipment_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id           bigint   NOT NULL REFERENCES sales.orders (order_id) ON DELETE CASCADE,
    warehouse_id       smallint NOT NULL REFERENCES logistics.warehouses (warehouse_id),
    carrier            text NOT NULL,
    tracking_number    text NOT NULL UNIQUE,
    status             logistics.shipment_status NOT NULL DEFAULT 'label_created',
    shipped_at         timestamptz,
    estimated_delivery date,
    delivered_at       timestamptz,
    CONSTRAINT shipments_delivery_after_ship CHECK (delivered_at IS NULL OR delivered_at >= shipped_at)
);
CREATE INDEX shipments_order_id_idx ON logistics.shipments (order_id);

CREATE TABLE logistics.shipment_events (
    event_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id bigint NOT NULL REFERENCES logistics.shipments (shipment_id) ON DELETE CASCADE,
    status      logistics.shipment_status NOT NULL,
    location    text,
    details     jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL
);
CREATE INDEX shipment_events_shipment_idx ON logistics.shipment_events (shipment_id, occurred_at);

CREATE TABLE sales.returns (
    return_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_item_id bigint NOT NULL UNIQUE REFERENCES sales.order_items (order_item_id) ON DELETE CASCADE,
    reason        text NOT NULL CHECK (reason IN ('damaged', 'wrong_item', 'size_issue', 'not_as_described', 'changed_mind')),
    status        text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'approved', 'rejected', 'received', 'refunded')),
    refund_id     bigint REFERENCES sales.refunds (refund_id),
    requested_at  timestamptz NOT NULL DEFAULT now(),
    resolved_at   timestamptz
);

-- =====================================================================
-- CATALOG (continued): reviews need order_items for "verified purchase"
-- =====================================================================
CREATE TABLE catalog.reviews (
    review_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id    bigint NOT NULL REFERENCES catalog.products (product_id) ON DELETE CASCADE,
    user_id       bigint NOT NULL REFERENCES core.users (user_id) ON DELETE CASCADE,
    order_item_id bigint UNIQUE REFERENCES sales.order_items (order_item_id) ON DELETE SET NULL,
    rating        core.rating NOT NULL,
    title         text,
    body          text,
    image_urls    text[] NOT NULL DEFAULT '{}',
    helpful_count int NOT NULL DEFAULT 0,
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (product_id, user_id)                          -- one review per product per user
);
CREATE INDEX reviews_product_id_idx ON catalog.reviews (product_id);

CREATE TABLE catalog.review_votes (
    review_id  bigint NOT NULL REFERENCES catalog.reviews (review_id) ON DELETE CASCADE,
    user_id    bigint NOT NULL REFERENCES core.users (user_id) ON DELETE CASCADE,
    is_helpful boolean NOT NULL,
    voted_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (review_id, user_id)
);

-- =====================================================================
-- AUDIT
-- =====================================================================
CREATE TABLE audit.audit_log (
    audit_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name text NOT NULL,
    operation  text NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')),
    row_pk     text,
    old_data   jsonb,
    new_data   jsonb,
    changed_by text NOT NULL DEFAULT current_user,
    changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- =====================================================================
-- ANALYTICS: declaratively partitioned by month (see chapter 18)
-- Partitions are created by the seed script for the data's date range.
-- =====================================================================
CREATE TABLE analytics.events (
    event_id    bigint GENERATED ALWAYS AS IDENTITY,
    user_id     bigint,                       -- NULL for anonymous visitors (no FK on purpose: high volume)
    session_id  uuid   NOT NULL,
    event_type  text   NOT NULL CHECK (event_type IN ('page_view', 'search', 'product_view', 'add_to_cart', 'remove_from_cart', 'checkout_start', 'purchase')),
    product_id  bigint,
    properties  jsonb  NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    PRIMARY KEY (event_id, occurred_at)       -- partition key must be part of the PK
) PARTITION BY RANGE (occurred_at);

CREATE TABLE analytics.events_default PARTITION OF analytics.events DEFAULT;
