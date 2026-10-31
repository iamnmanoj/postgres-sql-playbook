-- =====================================================================
--  Chapter 13 · Solutions — full-text search & fuzzy matching
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- [E13.01] Phrase-ish search
-- Keywords: plainto_tsquery(), @@
SELECT name FROM catalog.products
WHERE search_vector @@ plainto_tsquery('english', 'stainless steel')
LIMIT 5;

-- [E13.02] english vs simple config
-- Keywords: to_tsvector()
SELECT to_tsvector('english', 'Kids love these building blocks!') AS english,
       to_tsvector('simple',  'Kids love these building blocks!') AS simple;

-- [E13.03] Ranked reviews with snippets
-- Keywords: ts_rank(), ts_headline()
SELECT review_id,
       round(ts_rank(to_tsvector('english', coalesce(body, '')), q)::numeric, 4) AS rank,
       ts_headline('english', body, q) AS snippet
FROM catalog.reviews, to_tsquery('english', 'quality') AS q
WHERE to_tsvector('english', coalesce(body, '')) @@ q
ORDER BY rank DESC
LIMIT 5;

-- [E13.04] Multi-prefix search-as-you-type
-- Keywords: :*, to_tsquery(), string_agg()
SELECT name
FROM catalog.products
WHERE search_vector @@ to_tsquery('english',
        (SELECT string_agg(w || ':*', ' & ') FROM regexp_split_to_table('mech key', '\s+') AS w))
LIMIT 5;

-- [E13.05] Did-you-mean on categories
-- Keywords: similarity(), <->
SELECT name, round(similarity(name, 'smartwach')::numeric, 3) AS sim
FROM catalog.categories
ORDER BY name <-> 'smartwach'
LIMIT 3;

-- [E13.06] OR / NOT search restricted to a category
-- Keywords: websearch_to_tsquery() with or / -, ts_rank()
SELECT p.name, p.base_price, round(ts_rank(p.search_vector, q)::numeric, 4) AS rank
FROM catalog.products p
JOIN catalog.categories c USING (category_id),
     websearch_to_tsquery('english', 'yoga or dumbbell -set') AS q
WHERE c.slug = 'fitness' AND p.search_vector @@ q
ORDER BY rank DESC, p.base_price
LIMIT 10;

-- [E13.07] Search → product view conversion per term
-- Keywords: EXISTS, FILTER, ->>
SELECT s.properties ->> 'query' AS term,
       count(*) AS searches,
       round(100.0 * count(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM analytics.events v
           WHERE v.session_id = s.session_id AND v.event_type = 'product_view')) / count(*), 1) AS pct_viewed_product
FROM analytics.events s
WHERE s.event_type = 'search'
GROUP BY 1
ORDER BY searches DESC;
