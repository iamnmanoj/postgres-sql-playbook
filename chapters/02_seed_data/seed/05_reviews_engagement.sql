-- Reviews, review votes, seller ratings & payouts, notifications, carts,
-- wishlists, and the partitioned click-stream table.

CREATE TEMP TABLE seed_review_text (sentiment text, titles text[], phrases text[]);
INSERT INTO seed_review_text VALUES
 ('positive', ARRAY['Absolutely love it','Great value for money','Exceeded expectations','Highly recommended','Five stars!'],
              ARRAY['Battery life is excellent.','Delivery was quick and packaging was good.','Build quality feels premium.',
                    'Fits perfectly.','Sound quality is amazing.','Looks exactly like the pictures.','My kids love it.',
                    'Comfortable for all-day use.','Worth every rupee.']),
 ('neutral',  ARRAY['Decent product','Okay for the price','Average quality','Does the job'],
              ARRAY['Packaging could be better.','Colour is slightly different from the photo.','Took a while to arrive.',
                    'Instructions were confusing.','Good but a bit overpriced.']),
 ('negative', ARRAY['Disappointed','Stopped working','Poor quality','Not as described','Waste of money'],
              ARRAY['Stopped working after two weeks.','The colour faded after the first wash.','Arrived damaged.',
                    'Customer support was unhelpful.','Battery drains quickly.','Size runs very small.','Smells of cheap plastic.']);

-- Verified-purchase reviews: ~30% of delivered items, one review per (product, user)
INSERT INTO catalog.reviews (product_id, user_id, order_item_id, rating, title, body, image_urls, created_at)
SELECT r.product_id, r.user_id, r.order_item_id, r.rating,
       t.titles[1 + floor(r.r1 * cardinality(t.titles))::int],
       CASE WHEN r.r2 < 0.15 THEN NULL
            ELSE t.phrases[1 + floor(r.r2 * cardinality(t.phrases))::int] || ' ' ||
                 t.phrases[1 + floor(r.r3 * cardinality(t.phrases))::int] END,
       CASE WHEN r.r3 < 0.1 THEN ARRAY['https://cdn.shopsphere.test/r/' || r.order_item_id || '/1.jpg'] ELSE '{}' END,
       r.created_at
FROM (
    SELECT DISTINCT ON (v.product_id, o.user_id)
           v.product_id, o.user_id, oi.order_item_id,
           CASE WHEN x.rr < 0.45 THEN 5 WHEN x.rr < 0.70 THEN 4 WHEN x.rr < 0.82 THEN 3 WHEN x.rr < 0.90 THEN 2 ELSE 1 END AS rating,
           random() AS r1, random() AS r2, random() AS r3,
           least(now(), s.delivered_at + random() * interval '20 days') AS created_at
    FROM sales.order_items oi
    JOIN sales.orders o ON o.order_id = oi.order_id AND o.status = 'delivered'
    JOIN logistics.shipments s ON s.order_id = o.order_id
    JOIN catalog.product_variants v ON v.variant_id = oi.variant_id
    CROSS JOIN LATERAL (SELECT random() AS rr, oi.order_item_id AS _corr) x
    WHERE oi.order_item_id % 10 < 3
    ORDER BY v.product_id, o.user_id, oi.order_item_id
) r
JOIN seed_review_text t ON t.sentiment = CASE WHEN r.rating >= 4 THEN 'positive' WHEN r.rating = 3 THEN 'neutral' ELSE 'negative' END;

-- A few unverified reviews (no order_item_id)
INSERT INTO catalog.reviews (product_id, user_id, rating, title, created_at)
SELECT 1 + floor(random() * 3000)::bigint, 1 + floor(random() * 5000)::bigint,
       1 + floor(random() * 5)::int, 'Quick review', now() - random() * interval '300 days'
FROM generate_series(1, 800)
ON CONFLICT (product_id, user_id) DO NOTHING;

-- Helpful / not helpful votes, then a denormalised counter
INSERT INTO catalog.review_votes (review_id, user_id, is_helpful, voted_at)
SELECT 1 + floor(random() * (SELECT max(review_id) FROM catalog.reviews))::bigint,
       1 + floor(random() * 5000)::bigint,
       random() < 0.8,
       now() - random() * interval '200 days'
FROM generate_series(1, 25000)
ON CONFLICT DO NOTHING;

UPDATE catalog.reviews r
SET helpful_count = v.cnt
FROM (SELECT review_id, count(*) FILTER (WHERE is_helpful) AS cnt FROM catalog.review_votes GROUP BY review_id) v
WHERE v.review_id = r.review_id;

UPDATE core.sellers s
SET rating_avg = t.avg_rating
FROM (SELECT p.seller_id, round(avg(r.rating), 2) AS avg_rating
      FROM catalog.reviews r JOIN catalog.products p USING (product_id)
      GROUP BY p.seller_id) t
WHERE t.seller_id = s.seller_id;

-- Monthly seller payouts for the last 12 months (delivered items only)
INSERT INTO core.seller_payouts (seller_id, period, gross_sales, commission, status, paid_at)
SELECT oi.seller_id,
       daterange(m.month_start::date, (m.month_start + interval '1 month')::date),
       sum(oi.line_total),
       round(sum(oi.line_total) * s.commission_rate, 2),
       CASE WHEN NOT s.is_verified THEN 'on_hold'
            WHEN m.month_start < date_trunc('month', now()) THEN 'paid'
            ELSE 'scheduled' END,
       CASE WHEN s.is_verified AND m.month_start < date_trunc('month', now())
            THEN m.month_start + interval '1 month 7 days' END
FROM sales.order_items oi
JOIN sales.orders o ON o.order_id = oi.order_id AND o.status = 'delivered'
JOIN core.sellers s ON s.seller_id = oi.seller_id
CROSS JOIN LATERAL (SELECT date_trunc('month', o.placed_at) AS month_start) m
WHERE o.placed_at >= date_trunc('month', now()) - interval '12 months'
GROUP BY oi.seller_id, m.month_start, s.commission_rate, s.is_verified;

-- Notifications: order confirmations, shipping updates, promotions
INSERT INTO core.notifications (user_id, channel, template, payload, sent_at, read_at)
SELECT o.user_id,
       (ARRAY['email','sms','push'])[1 + (o.order_id % 3)::int],
       'order_confirmed',
       jsonb_build_object('order_number', o.order_number, 'amount', o.grand_total),
       o.placed_at + interval '1 minute',
       CASE WHEN o.order_id % 3 <> 1 THEN o.placed_at + random() * interval '2 days' END
FROM sales.orders o
WHERE o.status <> 'pending' AND o.order_id % 2 = 0;

INSERT INTO core.notifications (user_id, channel, template, payload, sent_at, read_at)
SELECT u.user_id, 'push', 'promo',
       jsonb_build_object('campaign', 'cmp_' || g, 'discount_pct', 5 * (1 + g % 6)),
       now() - (g * interval '7 days'),
       CASE WHEN random() < 0.2 THEN now() - (g * interval '7 days') + interval '3 hours' END
FROM core.users u
CROSS JOIN generate_series(1, 4) AS g
WHERE u.user_id % 4 = 0 AND u.status = 'active' AND u.created_at < now() - (g * interval '7 days');

-- Carts (some abandoned long ago) and wishlists
INSERT INTO sales.carts (user_id, updated_at)
SELECT user_id, now() - random() * interval '90 days'
FROM core.users
WHERE status = 'active' AND user_id % 3 = 0;

INSERT INTO sales.cart_items (cart_id, variant_id, quantity, added_at)
SELECT c.cart_id,
       1 + floor(random() * (SELECT max(variant_id) FROM catalog.product_variants))::bigint,
       1 + floor(random() * 3)::int,
       c.updated_at - random() * interval '10 days'
FROM sales.carts c
CROSS JOIN LATERAL generate_series(1, (c.cart_id % 5)::int)      -- cart_id % 5 = 0 -> empty cart
ON CONFLICT DO NOTHING;

INSERT INTO sales.wishlists (user_id, product_id, added_at)
SELECT 1 + floor(random() * 5000)::bigint, 1 + floor(3000 * power(random(), 1.5))::bigint, now() - random() * interval '365 days'
FROM generate_series(1, 10000)
ON CONFLICT DO NOTHING;

-- Monthly partitions for analytics.events: 24 months back to 2 months ahead.
-- format() + EXECUTE = dynamic SQL; %I quotes identifiers, %L quotes literals.
DO $$
DECLARE
    m date;
BEGIN
    FOR m IN SELECT generate_series(date_trunc('month', now() - interval '24 months'),
                                    date_trunc('month', now() + interval '2 months'),
                                    interval '1 month')::date
    LOOP
        EXECUTE format('CREATE TABLE IF NOT EXISTS analytics.%I PARTITION OF analytics.events FOR VALUES FROM (%L) TO (%L)',
                       'events_' || to_char(m, 'YYYY_MM'), m, (m + interval '1 month')::date);
    END LOOP;
END $$;

-- ~60k browsing sessions over the last year; each walks a funnel and drops off
INSERT INTO analytics.events (user_id, session_id, event_type, product_id, properties, occurred_at)
SELECT s.user_id, s.session_id, f.event_type,
       CASE WHEN f.event_type IN ('product_view','add_to_cart','remove_from_cart','purchase') THEN s.product_id END,
       CASE f.event_type
         WHEN 'page_view'    THEN jsonb_build_object('path', '/', 'referrer', s.referrer)
         WHEN 'search'       THEN jsonb_build_object('query', s.query, 'results', (s.g * 13) % 200)
         WHEN 'product_view' THEN jsonb_build_object('source', (ARRAY['search','home','recommendation','wishlist'])[1 + s.g % 4])
         WHEN 'add_to_cart'  THEN jsonb_build_object('quantity', 1 + s.g % 2)
         WHEN 'purchase'     THEN jsonb_build_object('payment', (ARRAY['upi','card','cod'])[1 + s.g % 3])
         ELSE '{}'::jsonb
       END,
       s.started_at + f.step * interval '90 seconds'
FROM (
    SELECT g,
           gen_random_uuid() AS session_id,
           CASE WHEN random() < 0.7 THEN 1 + floor(random() * 5000)::bigint END AS user_id,
           1 + floor(3000 * power(random(), 2))::bigint AS product_id,
           now() - interval '15 minutes' - random() * interval '365 days' AS started_at,
           random() AS depth,
           (ARRAY['wireless earbuds','running shoes','gaming laptop','yoga mat','air fryer','cotton t-shirt',
                  'mixer grinder','bluetooth speaker','gaming mouse','sunscreen spf 50','trekking backpack',
                  'smartwatch','headphnes','board game for kids'])[1 + floor(random() * 14)::int] AS query,
           (ARRAY['google','direct','instagram','email','facebook'])[1 + floor(random() * 5)::int] AS referrer
    FROM generate_series(1, 60000) AS g
) s
CROSS JOIN LATERAL (VALUES (1, 'page_view', 1.00), (2, 'search', 0.70), (3, 'product_view', 0.60),
                           (4, 'add_to_cart', 0.25), (5, 'remove_from_cart', 0.03),
                           (6, 'checkout_start', 0.12), (7, 'purchase', 0.07)) AS f(step, event_type, reach)
WHERE s.depth < f.reach;
