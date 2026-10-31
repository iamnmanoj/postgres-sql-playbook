# Contributing

Thanks for improving the ShopSphere PostgreSQL playbook! This guide covers the conventions every change must follow.

## Setup
```bash
cp .env.example .env            # optional: change ports/password
scripts/reset.sh                # PostgreSQL 17 in Docker + schema + seed data
(cd webapp && npm ci)           # web app dependencies (Node >= 20, see .nvmrc)
scripts/web.sh                  # or: cd webapp && npm start
```

## Before you open a pull request
```bash
scripts/ci.sh                   # exactly what CI runs
```
It runs the web app unit tests and syntax check, verifies the generated docs are current, executes every chapter
(`queries.sql` + `solutions.sql`) on a fresh database, and finally runs every cell and grades every exercise through the
web app. **All of it must pass.**

## Repository layout
| Path | Contents |
|---|---|
| `chapters/NN_topic/` | `README.md` (lesson), `queries.sql`, `exercises.sql`, `solutions.sql` |
| `chapters/01_ddl_schema/schema.sql`, `chapters/02_seed_data/` | the app schema and the data generator |
| `scripts/` | `reset.sh`, `psql.sh`, `run_all.sh`, `check.sh`, `web.sh`, `ci.sh`, `build_index.py` |
| `webapp/` | the interactive web app (see [webapp/README.md](webapp/README.md)) |
| `GLOSSARY.md`, `KEYWORD_INDEX.md` | **generated**: never edit by hand, run `python3 scripts/build_index.py` |

## Writing chapter SQL
Every query in `queries.sql` uses this exact header. The index builder and the web app both parse it:
```sql
-- =====================================================================
-- SECTION: Grouping basics
-- =====================================================================

-- ---------------------------------------------------------------------
-- [Q05.03] Short title
-- Keywords: GROUP BY, HAVING, sum()
-- Business question: The real ShopSphere question this query answers.
-- Note: optional extra lines (Note: / Try: / Expected:)
-- ---------------------------------------------------------------------
SELECT …;
```
Exercises use `-- [E05.01] (easy|medium|hard) question…` in `exercises.sql` (comments only), and the same ID header in `solutions.sql`.

Rules:
1. **No duplicate lessons.** Each query must teach something new and stay within its chapter's topic.
2. IDs are sequential with no gaps (`build_index.py` enforces this). Exercises and solutions must match one-to-one.
3. Use **schema-qualified names** (`sales.orders`).
4. Files must be **idempotent**: they must run cleanly after `scripts/reset.sh`, after all previous chapters, and twice in a row (`scripts/check.sh 05_aggregation/queries.sql`).
5. **Never permanently change seeded data.** Wrap DML on app tables in `BEGIN … ROLLBACK`, and put demo objects in a `playground_NN` schema.
6. Demonstrate errors without aborting the script by using a `DO $$ … EXCEPTION WHEN … THEN RAISE NOTICE … $$` block.
7. Filter time relative to `now()`, because the data set is generated relative to the build date.
8. Keep output readable with `LIMIT` (≤ 20 rows) unless the result is naturally small.
9. Every chapter README has the sections *What you'll learn*, *Concepts*, *Keywords & functions* (a table that feeds the glossary), *Gotchas* and *Run it*.
10. After changing headers or README keyword tables, run `python3 scripts/build_index.py` and commit the regenerated files.

## Web app code
- No build step: plain ES modules in `webapp/public`, and Express + `pg` on the server.
- Add unit tests in `webapp/test/*.test.js` (`node:test`) for parser and execution logic.
- The app runs SQL as a superuser and must stay bound to `127.0.0.1`.

## Commits
Use [Conventional Commits](https://www.conventionalcommits.org/), for example `feat(webapp): …`, `fix(ch09): …`, `docs: …`, `ci: …`, `chore: …`.
Never commit `node_modules/`, `.env` files, database dumps or editor settings (see `.gitignore`).
