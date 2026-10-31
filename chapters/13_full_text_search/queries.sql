-- =====================================================================
--  Chapter 13 · Full-text search & fuzzy matching
--  Creates search indexes (idempotent). Read-only otherwise.
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- =====================================================================
-- SECTION: Documents and queries
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q13.01] Turn text into a searchable document
-- Keywords: to_tsvector(), tsvector, lexemes, stop words, stemming
-- Note: 'english' config lower-cases, removes stop words (the, and, for) and stems (charging → charg).
-- ---------------------------------------------------------------------
SELECT to_tsvector('english', 'The Voltix Smartphone offers fast charging and long battery life.') AS english,
       to_tsvector('simple',  'The Voltix Smartphone offers fast charging and long battery life.') AS simple;

-- ---------------------------------------------------------------------
-- [Q13.02] Build queries and match them
-- Keywords: to_tsquery(), @@, & (AND), | (OR), ! (NOT), <-> (FOLLOWED BY)
-- Business question: Products about charging AND battery, but NOT power banks.
-- ---------------------------------------------------------------------
SELECT name
FROM catalog.products
WHERE search_vector @@ to_tsquery('english', 'charging & battery & !bank')
LIMIT 5;
SELECT to_tsquery('english', 'noise <-> cancellation') AS phrase_query,
       to_tsquery('english', 'wireless | bluetooth')   AS or_query;

-- ---------------------------------------------------------------------
-- [Q13.03] Parse what users actually type
-- Keywords: plainto_tsquery(), phraseto_tsquery(), websearch_to_tsquery()
-- Business question: The search box receives: wireless earbuds "noise cancellation" -case
-- ---------------------------------------------------------------------
SELECT plainto_tsquery('english', 'wireless earbuds')                              AS plain,      -- AND of words
       phraseto_tsquery('english', 'noise cancellation')                           AS phrase,     -- words in order
       websearch_to_tsquery('english', 'wireless earbuds "noise cancellation" -case') AS websearch; -- Google-like
SELECT name
FROM catalog.products
WHERE search_vector @@ websearch_to_tsquery('english', 'wireless earbuds "noise cancellation" -case')
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q13.04] Prefix matching for search-as-you-type
-- Keywords: :* (prefix)
-- Business question: The user has typed "headph".
-- ---------------------------------------------------------------------
SELECT name FROM catalog.products
WHERE search_vector @@ to_tsquery('english', 'headph:*')
LIMIT 5;

-- ---------------------------------------------------------------------
-- [Q13.05] Search ad-hoc text without a stored column
-- Keywords: to_tsvector() on the fly, coalesce()
-- Business question: Search review bodies for "battery" problems.
-- ---------------------------------------------------------------------
SELECT review_id, rating, body
FROM catalog.reviews
WHERE to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, '')) @@ to_tsquery('english', 'battery & (drain | quickly)')
LIMIT 5;

-- =====================================================================
-- SECTION: Ranking & highlighting
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q13.06] Weight fields: name matters more than description
-- Keywords: setweight(), weights A/B/C/D, the generated search_vector column
-- Note: catalog.products.search_vector = setweight(name,'A') || setweight(description,'B').
-- ---------------------------------------------------------------------
SELECT name, search_vector FROM catalog.products WHERE product_id = 1;

-- ---------------------------------------------------------------------
-- [Q13.07] Order results by relevance
-- Keywords: ts_rank(), ts_rank_cd(), normalization
-- Business question: Best matches for "gaming laptop".
-- ---------------------------------------------------------------------
SELECT name,
       round(ts_rank(search_vector, q)::numeric, 4)    AS rank,
       round(ts_rank_cd(search_vector, q)::numeric, 4) AS rank_cover_density,
       round(ts_rank(search_vector, q, 1)::numeric, 4) AS rank_len_normalized
FROM catalog.products, websearch_to_tsquery('english', 'gaming laptop') AS q
WHERE search_vector @@ q
ORDER BY rank DESC
LIMIT 8;

-- ---------------------------------------------------------------------
-- [Q13.08] Highlight matching words in results
-- Keywords: ts_headline()
-- Business question: Show search snippets with the matched words in bold.
-- ---------------------------------------------------------------------
SELECT name,
       ts_headline('english', description, q, 'StartSel=<b>, StopSel=</b>, MaxWords=12, MinWords=5') AS snippet
FROM catalog.products, websearch_to_tsquery('english', 'water resistant battery') AS q
WHERE search_vector @@ q
LIMIT 5;

-- =====================================================================
-- SECTION: Under the hood
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q13.09] See how text is parsed and normalised
-- Keywords: ts_debug(), ts_lexize(), dictionaries
-- ---------------------------------------------------------------------
SELECT alias, token, dictionaries, lexemes
FROM ts_debug('english', 'Running shoes for 5G-ready runners!');
SELECT ts_lexize('english_stem', 'charging') AS stem, ts_lexize('english_stem', 'the') AS stop_word;

-- ---------------------------------------------------------------------
-- [Q13.10] Language configs matter
-- Keywords: text search configuration, default_text_search_config, cfgname
-- ---------------------------------------------------------------------
SHOW default_text_search_config;
SELECT cfgname FROM pg_ts_config ORDER BY cfgname LIMIT 8;
SELECT to_tsvector('english', 'running runs ran') AS english_stems,
       to_tsvector('simple', 'running runs ran')  AS simple_no_stems;

-- ---------------------------------------------------------------------
-- [Q13.11] Remove accents before indexing
-- Keywords: unaccent()
-- Business question: "Café" and "cafe" should match.
-- ---------------------------------------------------------------------
SELECT unaccent('Café Crème Brûlée') AS plain,
       to_tsvector('simple', unaccent('Café Crème')) @@ plainto_tsquery('simple', 'cafe') AS matches;

-- =====================================================================
-- SECTION: Indexing full-text search
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q13.12] A GIN index makes @@ fast
-- Keywords: CREATE INDEX … USING gin (tsvector), EXPLAIN
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix13_products_search ON catalog.products USING gin (search_vector);
ANALYZE catalog.products;
EXPLAIN (COSTS OFF)
SELECT product_id FROM catalog.products WHERE search_vector @@ to_tsquery('english', 'laptop');

-- ---------------------------------------------------------------------
-- [Q13.13] An expression index for text without a stored tsvector column
-- Keywords: GIN expression index, to_tsvector() IMMUTABLE with explicit config
-- Note: You MUST pass the config ('english') for the expression to be indexable.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix13_reviews_fts
    ON catalog.reviews USING gin (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, '')));
ANALYZE catalog.reviews;
EXPLAIN (COSTS OFF)
SELECT review_id FROM catalog.reviews
WHERE to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, '')) @@ to_tsquery('english', 'damaged');

-- =====================================================================
-- SECTION: Fuzzy matching with pg_trgm
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q13.14] Trigrams and similarity
-- Keywords: show_trgm(), similarity(), word_similarity()
-- Business question: How similar is the misspelled "headphnes" to "headphones"?
-- ---------------------------------------------------------------------
SELECT show_trgm('headphnes') AS trigrams,
       similarity('headphnes', 'headphones')                 AS similarity,
       word_similarity('headphnes', 'Auralux Headphones Pro 42') AS word_similarity;

-- ---------------------------------------------------------------------
-- [Q13.15] "Did you mean …?" — fuzzy search over product names
-- Keywords: % (similarity operator), <-> (distance), pg_trgm.similarity_threshold, <% (word similarity)
-- Business question: The search log contains 'headphnes'; suggest the closest product names.
-- ---------------------------------------------------------------------
SET pg_trgm.similarity_threshold = 0.3;
SELECT name, round(similarity(name, 'headphnes')::numeric, 3) AS sim
FROM catalog.products
WHERE 'headphnes' <% name                              -- word-similarity match
ORDER BY name <-> 'headphnes'                           -- distance = 1 - similarity
LIMIT 5;
RESET pg_trgm.similarity_threshold;

-- ---------------------------------------------------------------------
-- [Q13.16] Trigram indexes speed up fuzzy search AND ILIKE '%…%'
-- Keywords: gin_trgm_ops, gist_trgm_ops, ILIKE with index
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix13_products_name_trgm ON catalog.products USING gin (name gin_trgm_ops);
ANALYZE catalog.products;
EXPLAIN (COSTS OFF) SELECT name FROM catalog.products WHERE name ILIKE '%kettle%';
EXPLAIN (COSTS OFF) SELECT name FROM catalog.products WHERE name % 'Moniter';

-- ---------------------------------------------------------------------
-- [Q13.17] Search-log analysis: which searches have zero results?
-- Keywords: FTS on event properties, NOT EXISTS, websearch_to_tsquery()
-- Business question: Which customer searches return nothing (merchandising gaps)?
-- ---------------------------------------------------------------------
SELECT e.properties ->> 'query' AS search_term, count(*) AS searches
FROM analytics.events e
WHERE e.event_type = 'search'
  AND e.occurred_at >= now() - interval '90 days'
  AND NOT EXISTS (SELECT 1 FROM catalog.products p
                  WHERE p.search_vector @@ websearch_to_tsquery('english', e.properties ->> 'query'))
GROUP BY 1
ORDER BY searches DESC;

-- ---------------------------------------------------------------------
-- [Q13.18] Combine full-text relevance with fuzzy fallback
-- Keywords: UNION ALL, ranking blend, GROUP BY … max()
-- Business question: Search "moniter 4k": exact FTS hits first, then fuzzy name matches.
-- ---------------------------------------------------------------------
WITH input AS (SELECT 'moniter 4k'::text AS q),
fts AS (
    SELECT p.product_id, p.name, 1.0 + ts_rank(p.search_vector, websearch_to_tsquery('english', i.q)) AS score
    FROM catalog.products p, input i
    WHERE p.search_vector @@ websearch_to_tsquery('english', i.q)
),
fuzzy AS (
    SELECT p.product_id, p.name, word_similarity(i.q, p.name) AS score
    FROM catalog.products p, input i
    WHERE i.q <% p.name
)
SELECT product_id, name, round(max(score)::numeric, 3) AS score       -- a product found by both keeps its best score
FROM (SELECT * FROM fts UNION ALL SELECT * FROM fuzzy) s
GROUP BY product_id, name
ORDER BY score DESC, product_id
LIMIT 8;

-- ---------------------------------------------------------------------
-- [Q13.19] Autocomplete on category names with prefix + trigram
-- Keywords: ILIKE prefix, similarity ordering
-- Business question: The user typed "kit" in the category box.
-- ---------------------------------------------------------------------
SELECT name, round(similarity(name, 'kit')::numeric, 3) AS sim
FROM catalog.categories
WHERE name ILIKE 'kit%' OR name ILIKE '% kit%' OR name % 'kit'
ORDER BY name ILIKE 'kit%' DESC, sim DESC
LIMIT 5;
