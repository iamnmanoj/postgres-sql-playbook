# Chapter 16 · Functions & Procedures: Modular SQL & PL/pgSQL

[← Previous](../15_views_materialized/README.md) · [Index](../../README.md) · [Next →](../17_triggers/README.md)

## What you'll learn
- SQL functions: scalar, multi-column (OUT), set-returning (TABLE / SETOF), and `BEGIN ATOMIC` bodies
- Volatility (`IMMUTABLE`/`STABLE`/`VOLATILE`), `STRICT`, `PARALLEL SAFE`, defaults and named arguments
- PL/pgSQL: variables, `%TYPE`/`%ROWTYPE`, `IF`, loops, `RETURN NEXT/QUERY`, errors, dynamic SQL and cursors
- `VARIADIC`, polymorphic types and overloading
- Procedures (`CALL`) with transaction control, `DO` blocks, and `SECURITY DEFINER` done safely

## Concepts

### Function vs procedure
| | Function | Procedure (PG11+) |
|---|---|---|
| Called with | `SELECT f(…)`, in any expression, in `FROM` | `CALL p(…)` |
| Returns | a value, a row or a set | nothing (except `OUT`/`INOUT` params) |
| Can `COMMIT`/`ROLLBACK` inside | ❌ | ✅ (when not called inside an outer transaction block) |
| Use for | calculations, lookups, reusable queries | batch jobs, multi-step business operations |

### SQL functions (Q16.01–Q16.06)
`LANGUAGE sql` bodies are plain SQL. The planner can inline simple ones, which makes them very fast.
- Parameters are referenced by name (or `$1`) and may have `DEFAULT`s. Callers can use **named notation**: `f(rate => 0.12, amount => 100)`.
- `OUT` parameters return a record. `RETURNS TABLE (…)` and `RETURNS SETOF type` return sets, which you use in `FROM` like a table, including with `LATERAL`.
- `BEGIN ATOMIC … END` (PG14) is parsed when the function is created, so dependencies are tracked and a renamed table breaks loudly.

### Volatility matters
| Category | Promise | Allows |
|---|---|---|
| `IMMUTABLE` | same inputs → same result forever, no table reads | expression indexes, generated columns, constant folding |
| `STABLE` | same result within one statement; may read tables | use in index scans (`WHERE col = f()`) |
| `VOLATILE` (default) | anything (writes, `random()`, `clock_timestamp()`) | re-evaluated for every row |

Mislabelling a function, for example marking one that reads tables as `IMMUTABLE`, can produce **wrong results**.

### PL/pgSQL building blocks (Q16.07–Q16.13)
```sql
CREATE OR REPLACE FUNCTION f(args) RETURNS type LANGUAGE plpgsql AS $$
DECLARE  v type := default;  r sales.coupons%ROWTYPE;  x sales.coupons.code%TYPE;
BEGIN
    SELECT … INTO v …;                      IF NOT FOUND THEN … END IF;
    IF … THEN … ELSIF … ELSE … END IF;      CASE … WHEN … END CASE;
    FOR r IN SELECT … LOOP … END LOOP;      FOR i IN 1..10 LOOP … END LOOP;
    WHILE cond LOOP … END LOOP;             LOOP … EXIT WHEN …; CONTINUE WHEN …; END LOOP;
    FOREACH x IN ARRAY arr LOOP … END LOOP;
    RETURN NEXT;  RETURN QUERY SELECT …;    RETURN value;
    EXECUTE format('… %I … $1', ident) INTO v USING val;
    GET DIAGNOSTICS n = ROW_COUNT;          PERFORM some_query;
    RAISE NOTICE|WARNING|INFO|EXCEPTION 'msg %', v USING ERRCODE = '…', HINT = '…';
EXCEPTION WHEN unique_violation THEN …     WHEN others THEN GET STACKED DIAGNOSTICS …;
END $$;
```
- An `EXCEPTION` block creates a **savepoint**, so errors inside it are rolled back. It costs some performance, so don't wrap every loop iteration in one.
- **Dynamic SQL**: always use `format()` with `%I` for identifiers and `USING` for values. Never concatenate user input into SQL, because that causes SQL injection (Q16.11).

### Advanced signatures (Q16.14–Q16.16)
`VARIADIC text[]` accepts any number of arguments. `anyelement`, `anyarray` and `anycompatible` write one function for many types.
Overloading means the same name with different argument types, so `DROP FUNCTION` needs the signature.

### Procedures, DO and SECURITY DEFINER (Q16.17–Q16.21)
- Procedures can `COMMIT` between batches, which keeps locks and WAL bursts small (Q16.17). `OUT` parameters on procedures arrived in PG14.
- `DO $$ … $$` runs one-off anonymous PL/pgSQL.
- `SECURITY DEFINER` runs with the **owner's** privileges, like Unix setuid. Always add `SET search_path = …` and `REVOKE EXECUTE … FROM PUBLIC`, then grant to specific roles (ch19).

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `CREATE OR REPLACE FUNCTION … LANGUAGE sql` | SQL function | Q16.01 |
| `IMMUTABLE`, `STABLE`, `VOLATILE`, `STRICT`, `PARALLEL SAFE` | function properties | Q16.02 |
| `DEFAULT` args, named notation `=>` | flexible calls | Q16.03 |
| `BEGIN ATOMIC` | SQL-standard body | Q16.04 |
| `OUT` parameters | multi-column result | Q16.05 |
| `RETURNS TABLE`, `RETURNS SETOF` | set-returning functions | Q16.06 |
| `DECLARE`, `%TYPE`, `%ROWTYPE`, `SELECT INTO`, `IF/ELSIF`, `RAISE EXCEPTION` | PL/pgSQL basics | Q16.07 |
| `EXCEPTION WHEN`, `GET STACKED DIAGNOSTICS`, `RAISE WARNING` | error handling | Q16.08 |
| `FOREACH`, `LOOP`, `EXIT WHEN`, `CONTINUE WHEN`, `FOR … IN SELECT`, `WHILE`, `RETURN NEXT` | loops | Q16.09 |
| `RETURN QUERY` | return a result set | Q16.10 |
| `EXECUTE format() USING`, `%I`, `%L` | safe dynamic SQL | Q16.11 |
| `GET DIAGNOSTICS ROW_COUNT`, `FOUND`, `PERFORM` | statement status | Q16.12 |
| cursor `OPEN`/`FETCH`/`CLOSE` | chunked processing | Q16.13 |
| `VARIADIC` | variable arguments | Q16.14 |
| `anyelement`, `anyarray`, `anycompatible` | polymorphism | Q16.15 |
| overloading | same name, different types | Q16.16 |
| `CREATE PROCEDURE`, `CALL`, `COMMIT` in procedure, `INOUT` | procedures | Q16.17 |
| procedure with `OUT`, `ERRCODE` | business transaction | Q16.18 |
| `DO`, `RAISE INFO` | anonymous blocks | Q16.19 |
| `SECURITY DEFINER`, `SET search_path`, `REVOKE EXECUTE` | privileged functions | Q16.20 |
| `pg_proc`, `pg_get_functiondef()`, `DROP FUNCTION` | inspect and drop | Q16.21 |

## Gotchas
- Variable names that clash with column names cause "column reference is ambiguous" errors. Prefix parameters (`p_`) and variables (`v_`).
- `SELECT … INTO v` with no row leaves `v` NULL. Check `FOUND`, or use `INTO STRICT` to raise an error.
- A function called inside a transaction can't `COMMIT`. Only top-level `CALL`s of procedures can.
- `CREATE OR REPLACE` can't change the return type. Drop the function first.
- Heavy row-by-row PL/pgSQL loops are slow. Prefer a single set-based SQL statement wherever possible.

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/16_functions_procedures/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
