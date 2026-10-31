# Chapter 13 · Full-text search & fuzzy matching

[← Previous](../12_jsonb_arrays/README.md) · [Index](../../README.md) · [Next →](../14_indexes_performance/README.md)

## What you'll learn
- How PostgreSQL turns text into **documents** (`tsvector`) and searches with **queries** (`tsquery`)
- Parsing user input safely with `plainto_`, `phraseto_` and `websearch_to_tsquery`
- Relevance ranking, field weights and highlighted snippets
- Debugging tokenisation, and language configurations
- Indexing full-text search with GIN
- **Typo tolerance** with `pg_trgm`: similarity, "did you mean", and fast `ILIKE '%…%'`

## Concepts

### Documents and queries
`to_tsvector('english', text)` splits text into tokens, lower-cases them, drops **stop words** (the, and, for) and reduces words to **lexemes** (charging → `charg`). It also stores positions.
A `tsquery` combines lexemes with `&` (AND), `|` (OR), `!` (NOT), `<->` (followed by) and `:*` (prefix). `@@` tests whether a document matches a query (Q13.01–Q13.04).

| Function | Input | Good for |
|---|---|---|
| `to_tsquery` | operator syntax `'a & (b \| c)'` | programmatic queries (raises an error on bad syntax) |
| `plainto_tsquery` | plain words, ANDed together | simple boxes |
| `phraseto_tsquery` | words in order | exact phrases |
| `websearch_to_tsquery` | `word "phrase" or -exclude` | **user input**: never raises a syntax error |

### The ShopSphere search column
`catalog.products.search_vector` is a **generated column**:
`setweight(to_tsvector(name), 'A') || setweight(to_tsvector(description), 'B')`. Name matches therefore count more than description matches (Q13.06).

### Ranking and snippets (Q13.07–Q13.08)
`ts_rank` scores how often terms appear, and `ts_rank_cd` also rewards terms that appear close together. Both apply the A/B/C/D weights.
The normalisation flag (for example `1`) divides by document length. `ts_headline` builds a snippet with the matched words marked. It's expensive, so call it only on the final page of results.

### Under the hood (Q13.09–Q13.11)
`ts_debug` shows how each token is parsed and which dictionary handled it. `ts_lexize` tests a single dictionary.
The configuration decides stemming: `english` stems, `simple` doesn't. `unaccent` strips accents (`Café` → `Cafe`).

### Indexing (Q13.12–Q13.13)
A **GIN** index on a tsvector column or expression makes `@@` fast. For an expression index, the query must use the **same expression, including the config name**.

### Fuzzy matching with pg_trgm (Q13.14–Q13.19)
A trigram is a group of 3 consecutive characters. Two strings that share many trigrams are similar, which makes trigrams **tolerant of typos** (`headphnes` ≈ `headphones`).
| Operator / function | Meaning |
|---|---|
| `similarity(a, b)`, `a % b` | whole-string similarity (threshold `pg_trgm.similarity_threshold`, default 0.3) |
| `word_similarity(a, b)`, `a <% b` | does `a` closely match some part of `b`? (threshold 0.6) |
| `a <-> b` | distance = 1 − similarity; use `ORDER BY` for nearest-first |
| `gin_trgm_ops` / `gist_trgm_ops` | index operator classes. GIN also speeds up `LIKE`/`ILIKE '%x%'` and regex |

**FTS vs trigram.** Full-text search understands *words*, through stemming, stop words and ranking. Trigrams understand *spelling*. Real search boxes often combine both (Q13.18).

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `to_tsvector()`, `tsvector` | build a document | Q13.01 |
| `to_tsquery()`, `@@`, `&`, `\|`, `!`, `<->` | query and match | Q13.02 |
| `plainto_tsquery()`, `phraseto_tsquery()`, `websearch_to_tsquery()` | parse user input | Q13.03 |
| `:*` | prefix match | Q13.04 |
| on-the-fly `to_tsvector()` | search unindexed text | Q13.05 |
| `setweight()`, weights A–D | field importance | Q13.06 |
| `ts_rank()`, `ts_rank_cd()` | relevance | Q13.07 |
| `ts_headline()` | highlighted snippets | Q13.08 |
| `ts_debug()`, `ts_lexize()` | inspect parsing | Q13.09 |
| `default_text_search_config`, `pg_ts_config` | language configs | Q13.10 |
| `unaccent()` | strip accents | Q13.11 |
| GIN index on tsvector | fast FTS | Q13.12 |
| GIN expression index | FTS on an expression | Q13.13 |
| `show_trgm()`, `similarity()`, `word_similarity()` | trigram similarity | Q13.14 |
| `%`, `<%`, `<->`, `pg_trgm.similarity_threshold` | fuzzy operators | Q13.15 |
| `gin_trgm_ops`, indexed `ILIKE` | trigram index | Q13.16 |
| zero-result searches | search analytics | Q13.17 |
| FTS + fuzzy blend | hybrid search | Q13.18 |
| prefix + trigram autocomplete | autocomplete | Q13.19 |

## Gotchas
- `to_tsquery('user typed this')` raises errors on stray `&` or `!`. Use `websearch_to_tsquery` for user input.
- An expression index matches only when the query uses the exact same expression and config.
- Stemming is language specific. Brand names and SKUs are often better searched with the `simple` config or with trigrams.
- `ts_headline` re-parses the original text, so run it on the final, limited rows only.
- Very short queries (1–2 characters) produce few trigrams, so they're slow and noisy.
- For very large catalogs or advanced relevance tuning, dedicated engines (Elasticsearch, OpenSearch) or the `pg_search`/`ParadeDB` extensions may be better. PostgreSQL FTS goes surprisingly far, though.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/13_full_text_search/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
