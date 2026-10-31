-- =====================================================================
--  Chapter 13 · Exercises — full-text search & fuzzy matching
-- =====================================================================

-- [E13.01] (easy) Find products whose search_vector matches "stainless steel". Show 5 names.

-- [E13.02] (easy) Show the tsvector of the text 'Kids love these building blocks!' with the english and
--          simple configurations side by side.

-- [E13.03] (medium) Rank reviews mentioning "quality" by ts_rank and show a highlighted snippet of the body.

-- [E13.04] (medium) Implement search-as-you-type for the input "mech key" (both words are prefixes).

-- [E13.05] (medium) For the search term 'smartwach' (typo), suggest the 3 closest CATEGORY names with pg_trgm.

-- [E13.06] (hard) Search "yoga OR dumbbell" but NOT "set" with websearch_to_tsquery, restricted to the
--          'fitness' category, ordered by rank then price.

-- [E13.07] (hard) Using the search events, compute for each search term the % of sessions that went on to
--          a 'product_view' in the same session. Order by searches.
