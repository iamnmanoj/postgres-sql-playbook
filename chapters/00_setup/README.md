# Chapter 00 · Setup: run PostgreSQL and meet `psql`

[Index](../../README.md) · [Next →](../01_ddl_schema/README.md)

## What you'll learn
- Start a PostgreSQL 17 server in Docker with one command
- Build (and rebuild) the ShopSphere database
- Connect with `psql`, the official command-line client, and with GUI tools
- The `psql` meta-commands you'll use every day

## 1. Prerequisites
- **Docker Desktop** (Windows/macOS) or **Docker Engine + Compose v2** (Linux). Check with `docker compose version`.
- About 1 GB of free disk space.

## 2. Start the server and build the database
```bash
cd postgres-playbook
scripts/reset.sh          # starts the container (first time pulls postgres:17), creates the DB, loads schema + seed
```
`reset.sh` is safe to run any time you want a **clean database**. It drops `shopsphere`, runs
[`01_ddl_schema/schema.sql`](../01_ddl_schema/schema.sql), and then runs [`02_seed_data/seed.sql`](../02_seed_data/seed.sql). The whole thing takes about 15 seconds.

What [`docker-compose.yml`](../../docker-compose.yml) sets up:

| Setting | Value |
|---|---|
| Image | `postgres:17` |
| Container | `shopsphere-pg` |
| Host port | `5432` (override: `PG_PORT=5433 docker compose up -d`) |
| User / password | `postgres` / `postgres` |
| Database | `shopsphere` |
| Repo mounted at | `/playbook` inside the container (read-only), so `psql -f /playbook/...` works |
| Extra config | `shared_preload_libraries=pg_stat_statements` (used in chapter 14) |

Useful Docker commands:
```bash
docker compose ps                 # is it running?
docker compose logs -f db         # server log
docker compose stop               # stop (data is kept in the pgdata volume)
docker compose down -v            # remove container AND data volume (full wipe)
```

## 3. Connect
```bash
scripts/psql.sh                                     # interactive psql on shopsphere
scripts/psql.sh -c "SELECT count(*) FROM sales.orders"
scripts/psql.sh -e -f /playbook/chapters/03_select_filtering/queries.sql   # run a chapter (-e echoes each query)
DB=other_db scripts/psql.sh                         # another database
```
If `psql` is installed locally, you can also run `psql -h localhost -U postgres -d shopsphere` (password `postgres`).

**GUI options** (connect to `localhost:5432`, user `postgres`, password `postgres`):
- VS Code: the *PostgreSQL* extension by Microsoft, or *SQLTools* with its PostgreSQL driver
- pgAdmin 4, DBeaver, DataGrip, TablePlus

> Tip: In VS Code you can open any `queries.sql`, select one query and run just that query. That's the best way to work through the chapters.

## 4. psql survival kit

| Command | What it does |
|---|---|
| `\?` | help for meta-commands |
| `\h SELECT` | SQL syntax help for a command |
| `\l` | list databases |
| `\c dbname` | connect to another database |
| `\dn` | list schemas |
| `\dt sales.*` | list tables in a schema |
| `\d sales.orders` | describe a table (columns, indexes, constraints, triggers) |
| `\d+ sales.orders` | describe with storage, comments and size |
| `\dT+ sales.*` | list types (enums show their labels) |
| `\dD` | list domains |
| `\di`, `\dv`, `\dm`, `\df`, `\dx` | indexes, views, materialized views, functions, extensions |
| `\du` | list roles |
| `\dp sales.orders` | show privileges |
| `\x` (or `\x auto`) | expanded display, one column per line (great for wide rows/JSON) |
| `\timing on` | show how long each query took |
| `\e` | open the last query in your editor |
| `\i file.sql` / `\ir file.sql` | run a file (absolute / relative to the current file) |
| `\o out.txt` / `\o` | send results to a file / back to screen |
| `\copy` | client-side COPY (chapter 02) |
| `\set ON_ERROR_STOP on` | stop a script at the first error |
| `\pset null '∅'` | show NULLs visibly (highly recommended while learning) |
| `\conninfo` | who/where am I connected |
| `\q` | quit |

Put your favourite settings in `~/.psqlrc` (inside the container: `/root/.psqlrc`), for example:
```
\pset null '∅'
\timing on
\x auto
```

## 5. First look at the data
```sql
SHOW search_path;                        -- core, catalog, logistics, sales, audit, analytics, public
SELECT version();
\dn+
\dt+ sales.*
\d catalog.products
SELECT * FROM catalog.products LIMIT 3;
```
Because the database's `search_path` includes every app schema, `SELECT * FROM products` also works. The playbook still writes
`catalog.products` everywhere so you always know which schema a table lives in.

## 6. How each chapter is organised

| File | Purpose |
|---|---|
| `README.md` | the lesson: concepts, keyword table, gotchas |
| `queries.sql` | runnable examples; each one has an ID like `[Q05.03]` and a `Keywords:` line |
| `exercises.sql` | practice questions (comments only), so try them yourself first |
| `solutions.sql` | worked answers (runnable) |

Every query ID is listed in [KEYWORD_INDEX.md](../../KEYWORD_INDEX.md), and every keyword is explained in [GLOSSARY.md](../../GLOSSARY.md).

## Gotchas
- **Port 5432 already in use?** Another PostgreSQL is running locally. Start with `PG_PORT=5433 scripts/reset.sh` and connect to port 5433.
- **Changes lost?** `reset.sh` rebuilds from scratch, by design. Keep your own experiments in a separate `.sql` file.
- **`psql: FATAL: database "shopsphere" does not exist`**: run `scripts/reset.sh` first.
- Inside the container, file paths start with `/playbook/...`, not with your host path.
