# Chapter 12 · JSONB Arrays: Working with Semi-Structured Data

[← Previous](../11_transactions_locking/README.md) · [Index](../../README.md) · [Next →](../13_full_text_search/README.md)

## What you'll learn
- Reading JSONB: `->`, `->>`, `#>`, `#>>`, and casting extracted values
- Querying JSONB: containment `@>`/`<@` and key existence `?`, `?|`, `?&`
- Expanding JSONB into rows and typed columns, and building JSON from rows
- Modifying documents: `||`, `-`, `#-`, `jsonb_set`, `jsonb_insert`
- The SQL/JSON **path language** (`@?`, `@@`, `jsonb_path_*`) and the SQL-standard functions `JSON_VALUE`, `JSON_QUERY`, `JSON_EXISTS` and `JSON_TABLE` (PG16/17)
- Arrays: literals, slicing, searching, modifying, `unnest`

## Concepts

### json vs jsonb
`json` stores the original text, including whitespace, key order and duplicate keys. `jsonb` stores a parsed binary form: keys are de-duplicated (the last one wins), it's faster to query, and it can be **indexed** with GIN.
**Use `jsonb`.** ShopSphere uses it for `users.preferences`, `products.attributes`, `orders.metadata`, `payments.gateway_response` and `events.properties`.

### Operators cheat sheet
| Operator | Returns | Example |
|---|---|---|
| `->` key / index | jsonb | `metadata -> 'utm'`, `arr -> 0` |
| `->>` key / index | text | `metadata ->> 'channel'` |
| `#>` path | jsonb | `metadata #> '{utm,source}'` |
| `#>>` path | text | `metadata #>> '{utm,source}'` |
| `@>` / `<@` | boolean | `metadata @> '{"channel":"app"}'` |
| `?` / `?\|` / `?&` | boolean | key exists / any key / all keys |
| `\|\|` | jsonb | shallow merge (the right side wins) |
| `-` key / `-` text[] / `#-` path | jsonb | delete a key / several keys / a nested path |
| `@?` / `@@` | boolean | jsonpath exists / jsonpath predicate |

`->>` always returns **text**. Cast it before comparing numbers: `(attributes->>'pages')::int > 300` (Q12.03).

### Expanding and building (Q12.06–Q12.11)
- To rows: `jsonb_each[_text]`, `jsonb_object_keys`, `jsonb_array_elements[_text]`.
- To typed columns: `jsonb_to_record[set]` with a column definition list, or `jsonb_populate_record(NULL::type, doc)`.
- From SQL: `jsonb_build_object`, `jsonb_build_array`, `to_jsonb(row)`, `row_to_json`, and the aggregates `jsonb_agg` / `jsonb_object_agg` from ch05.

### Modifying (Q12.12–Q12.13)
`jsonb_set(doc, path, value, create_if_missing)` replaces or creates a value. `jsonb_insert(doc, path, value, insert_after)` inserts into arrays.
Each one returns a **new** document, and you `UPDATE` the column with it. PostgreSQL rewrites the whole value, so keep documents reasonably small.

### SQL/JSON path (Q12.14–Q12.15)
A mini-language: `$` is the root, `.key`, `[*]`, and `? (@ > 5)` filters. Variables are passed as JSON: `jsonb_path_exists(doc, '$.x ? (@ > $min)', '{"min": 8}')`.
It supports `like_regex`, `starts with`, arithmetic, and methods like `.size()`, `.type()` and `.double()`.

### SQL-standard JSON (Q12.16–Q12.18)
- PG16: the `IS JSON [OBJECT|ARRAY|SCALAR]` predicates, plus `JSON_OBJECT`, `JSON_ARRAY`, `JSON_OBJECTAGG` and `JSON_ARRAYAGG`.
- PG17: `JSON_VALUE` (a scalar with `RETURNING type` and `DEFAULT … ON EMPTY|ERROR`), `JSON_QUERY` (an object or array), `JSON_EXISTS`, and **`JSON_TABLE`**, which turns JSON into rows and columns, with `NESTED PATH` for arrays and `FOR ORDINALITY` for positions.

### Arrays (Q12.19–Q12.24)
- Arrays are **1-based**. `arr[2:3]` is a slice. `cardinality()` counts all elements, while `array_length(arr, dim)` counts one dimension.
- Search: `x = ANY(arr)`, containment `@>`/`<@`, and overlap `&&`. The last three are GIN-indexable (ch14).
- Modify: `array_append`, `array_prepend`, `array_cat` / `||`, `array_remove`, `array_replace`, `trim_array`.
- `unnest(arr) WITH ORDINALITY` gives each element with its position. `unnest(a, b)` zips arrays of the same length.
- When to use arrays: small, ordered lists of simple values (tags, image URLs). For anything you need to join, constrain or update item by item, use a child table.

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `->`, `->>` | get a field as jsonb / text | Q12.01 |
| `#>`, `#>>`, `-> 0` | path / array index | Q12.02 |
| `(->>)::type` | cast extracted values | Q12.03 |
| `@>`, `<@` | containment | Q12.04 |
| `?`, `?\|`, `?&` | key existence | Q12.05 |
| `jsonb_typeof()`, `jsonb_object_keys()`, `jsonb_array_length()`, `jsonb_pretty()` | inspect | Q12.06 |
| `jsonb_each()`, `jsonb_each_text()` | object to rows | Q12.07 |
| `jsonb_array_elements[_text]()` | array to rows | Q12.08 |
| `jsonb_to_record()`, `jsonb_populate_record()` | JSON to typed columns | Q12.09 |
| `jsonb_to_recordset()` | JSON array to a table | Q12.10 |
| `jsonb_build_object()`, `jsonb_build_array()`, `to_jsonb()`, `row_to_json()` | build JSON | Q12.11 |
| `\|\|`, `-`, `#-`, `jsonb_strip_nulls()` | merge / delete | Q12.12 |
| `jsonb_set()`, `jsonb_insert()` | modify nested values | Q12.13 |
| `@?`, `@@`, jsonpath | path predicates | Q12.14 |
| `jsonb_path_query()`, `_array()`, `_first()`, `jsonb_path_exists()` + vars | path extraction | Q12.15 |
| `IS JSON`, `JSON_OBJECT()`, `JSON_ARRAYAGG()` | SQL-standard JSON (PG16) | Q12.16 |
| `JSON_VALUE()`, `JSON_QUERY()`, `JSON_EXISTS()` | SQL-standard queries (PG17) | Q12.17 |
| `JSON_TABLE()`, `NESTED PATH`, `FOR ORDINALITY` | JSON to relational (PG17) | Q12.18 |
| `ARRAY[]`, `'{}'`, `[n]`, `[m:n]`, `array_length()`, `cardinality()` | array basics | Q12.19 |
| `= ANY()`, `@>`, `<@`, `&&` | array search | Q12.20 |
| `array_append()`, `array_prepend()`, `array_cat()`, `array_remove()`, `array_replace()`, `trim_array()` | modify arrays | Q12.21 |
| `array_position()`, `array_positions()` | find elements | Q12.22 |
| `unnest()`, `WITH ORDINALITY`, multi-arg `unnest()` | array to rows | Q12.23 |
| `array_to_string()`, array comparison | convert and compare | Q12.24 |

## Gotchas
- `->>` returns text, so `metadata->>'total' > '100'` compares **strings**. Cast it.
- `metadata->>'x' = 'y'` can't use a GIN index. `metadata @> '{"x":"y"}'` can (ch14).
- JSON `null` isn't SQL `NULL`: `'{"a":null}'::jsonb -> 'a'` is the JSON value `null`, while `->> 'a'` is SQL NULL.
- `jsonb_set` on a **NULL** document returns NULL. Use `COALESCE(doc, '{}')`.
- `'a' || ARRAY['b']` fails ("malformed array literal") because the untyped `'a'` is read as an array. Cast it with `'a'::text`.
- An empty array is contained in every array (`'{}' <@ anything` is true).
- Keep frequently filtered or joined attributes in real columns. JSONB has no statistics per key.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/12_jsonb_arrays/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
