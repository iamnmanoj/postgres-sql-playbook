# Chapter 04 · Built-in functions & casting

[← Previous](../03_select_filtering/README.md) · [Index](../../README.md) · [Next →](../05_aggregation/README.md)

## What you'll learn
- The string toolkit: cleaning, slicing, searching, replacing, formatting, regex, hashing
- Numeric functions, and the integer-division trap
- Date and time: "now" variants, truncation, extraction, intervals, parsing and formatting, time zones, binning
- Casting between types, and validating input safely

## Concepts

### Strings (Q04.01–Q04.11)
| Task | Functions |
|---|---|
| Size | `length`/`char_length` (characters), `octet_length` (bytes) |
| Case | `upper`, `lower`, `initcap` |
| Clean | `trim`/`btrim`, `ltrim`, `rtrim` (whitespace or chosen characters), `regexp_replace(…, 'g')` |
| Slice | `substring(s FROM i FOR n)`, `substr`, `left`, `right`, `split_part(s, delim, n)` |
| Search | `position(x IN s)`, `strpos(s, x)` (1-based, 0 when not found) |
| Replace | `replace` (substring), `translate` (character by character) |
| Pad | `lpad`, `rpad`, `repeat`, `reverse` |
| Join | `concat` (ignores NULL), `concat_ws(sep, …)` (skips NULL along with its separator), `\|\|` (NULL in, NULL out) |
| Format | `format('%s %I %L', …)`: `%I` quotes an identifier, `%L` quotes a literal (safe dynamic SQL) |
| Split | `string_to_array`, `string_to_table` (PG14), `array_to_string` |
| Regex | `regexp_matches`, `regexp_substr`, `regexp_count`, `regexp_like`, `regexp_instr` (PG15) |
| Hash/encode | `md5`, `sha256`, `encode`/`decode` (hex, base64), `convert_to`/`convert_from` |

### Numbers (Q04.12–Q04.15)
- `round(x, n)` accepts a **negative** n to round to tens or hundreds. `trunc` cuts digits off. `ceil` and `floor` round toward ±∞.
- **Integer ÷ integer = integer**: `7/2 = 3`. Cast one side (`::numeric`) or write `100.0` (Q04.13). This is the most common bug in percentage reports.
- `%` and `mod()` give the remainder. `div()` does integer division.
- `width_bucket(value, low, high, n)` builds equal-width histograms.

### Dates and times (Q04.16–Q04.25)
- `now()` = `current_timestamp` = `transaction_timestamp()`. It's **frozen** for the whole transaction. `clock_timestamp()` returns the real time at each call.
- `date_trunc('week'|'month'|…, ts)` floors a timestamp to the start of a unit. Use it to group by period.
- `extract(field FROM ts)` / `date_part('field', ts)` pull out `year`, `month`, `dow` (0 = Sunday), `isodow` (1 = Monday), `quarter`, `epoch`, and more.
- Arithmetic: `ts - ts → interval`, `date - date → integer days`, `date + int → date`, `ts + interval → ts`. `age(a, b)` gives a "years mons days" interval.
- Build values with `make_date`, `make_timestamptz` and `make_interval(days => 5)`. Format with `to_char` (`FM` removes padding). Parse with `to_date`, `to_timestamp` and `to_number`.
- **Time zones**: `timestamptz` is stored in UTC and shown in the session's `TimeZone`. `ts AT TIME ZONE 'Asia/Kolkata'` converts to local wall-clock time.
- `date_bin(stride, ts, origin)` (PG14) buckets times into any width, such as 15 minutes.
- The `justify_*` functions normalise intervals, and `OVERLAPS` tests whether two periods intersect.

### Casting (Q04.26–Q04.27)
`CAST(x AS type)` is the SQL standard, and `x::type` is PostgreSQL shorthand. `pg_typeof(expr)` tells you the type of an expression.
`pg_input_is_valid(text, type)` (PG16) checks input **without** raising an error.

### Misc (Q04.28)
`gen_random_uuid()`, `current_database()`, `pg_backend_pid()`, and `num_nulls()`/`num_nonnulls()` for profile-completeness checks.

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `length()`, `char_length()`, `octet_length()` | string size | Q04.01 |
| `upper()`, `lower()`, `initcap()` | change case | Q04.01 |
| `trim()`, `btrim()`, `ltrim()`, `rtrim()` | strip characters | Q04.02 |
| `regexp_replace()` | regex replace | Q04.02 |
| `substring()`, `substr()`, `left()`, `right()`, `split_part()` | extract parts | Q04.03 |
| `position()`, `strpos()` | find a substring | Q04.04 |
| `replace()`, `translate()` | replace text or characters | Q04.05 |
| `lpad()`, `rpad()`, `repeat()`, `reverse()` | pad and repeat | Q04.06 |
| `concat()`, `concat_ws()` | NULL-safe concatenation | Q04.07 |
| `format()`, `quote_ident()`, `quote_literal()` | formatting and safe quoting | Q04.08 |
| `string_to_array()`, `string_to_table()`, `array_to_string()` | split and join | Q04.09 |
| `regexp_matches()`, `regexp_substr()`, `regexp_count()`, `regexp_like()` | regex functions | Q04.10 |
| `md5()`, `sha256()`, `encode()`, `decode()`, `convert_to()`, `convert_from()` | hashing and encoding | Q04.11 |
| `round()`, `trunc()`, `ceil()`, `floor()` | rounding | Q04.12 |
| `/`, `div()`, `%`, `mod()` | division and remainder | Q04.13 |
| `abs()`, `power()`, `sqrt()`, `cbrt()`, `exp()`, `ln()`, `log()`, `sign()` | math | Q04.14 |
| `width_bucket()` | histogram buckets | Q04.15 |
| `now()`, `clock_timestamp()`, `current_date`, `localtimestamp`, … | current time | Q04.16 |
| `date_trunc()` | truncate to a unit | Q04.17 |
| `extract()`, `date_part()` | date fields | Q04.18 |
| `age()`, interval arithmetic | durations | Q04.19 |
| `make_date()`, `make_timestamptz()`, `make_interval()` | build values from parts | Q04.20 |
| `to_char()` | format a date or number as text | Q04.21 |
| `to_date()`, `to_timestamp()`, `to_number()` | parse text | Q04.22 |
| `AT TIME ZONE`, `timezone()`, `SET TIME ZONE` | time-zone conversion | Q04.23 |
| `date_bin()` | arbitrary time buckets | Q04.24 |
| `justify_days()`, `justify_hours()`, `justify_interval()`, `OVERLAPS`, `isfinite()` | interval helpers | Q04.25 |
| `CAST()`, `::`, `pg_typeof()` | casting and type inspection | Q04.26 |
| `pg_input_is_valid()` | safe input validation | Q04.27 |
| `gen_random_uuid()`, `current_database()`, `pg_backend_pid()`, `num_nulls()`, `num_nonnulls()` | misc helpers | Q04.28 |

## Gotchas
- `count(*) * 100 / count(*)` uses integer math. Multiply by `100.0` instead.
- String positions are **1-based**, so `substr(s, 0, 3)` returns only 2 characters.
- `'a' || NULL` is NULL, while `concat('a', NULL)` is `'a'`.
- `extract(dow)` treats Sunday as 0, and `isodow` treats Monday as 1.
- `date_trunc('week', …)` always starts weeks on **Monday**.
- `now()` doesn't move inside a transaction. Use `clock_timestamp()` to measure durations.
- `to_char` pads with spaces by default. Use the `FM` prefix to remove them.
- `timestamp AT TIME ZONE` and `timestamptz AT TIME ZONE` convert in **opposite** directions.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/04_builtin_functions/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
