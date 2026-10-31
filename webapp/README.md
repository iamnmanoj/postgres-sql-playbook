# ShopSphere SQL Playbook: interactive web app

A browser front-end for the whole playbook. It lets you read every lesson, run every query against the live database, and practise with exercises that are **checked automatically**.


## Start it

**With Docker** (recommended, nothing else to install):
```bash
scripts/web.sh                 # builds the web image, starts db + web, builds the database on first run
# → http://localhost:3000
```
`scripts/web.sh --rebuild` rebuilds the image after you change the web app code. Chapter files are read **live** from the repo,
so edits to `chapters/**` appear on reload without a rebuild.

**Without Docker for the app** (Node ≥ 20, database still in Docker):
```bash
scripts/reset.sh               # once, to create the database
cd webapp && npm install && npm start
# → http://localhost:3000   (PORT, HOST, PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE, PLAYBOOK_DIR are configurable)
```

## What you can do

| Area | Features |
|---|---|
| **Lesson tab** | The chapter README, rendered with highlighted SQL, a Mermaid ER diagram, clickable query IDs (`Q05.07` jumps to the query) and "▶ Try in scratchpad" buttons |
| **Queries tab** | Every query is an editable notebook **cell** showing its ID, business question and keywords. Each cell has ▶ Run, 🔍 Explain (EXPLAIN ANALYZE, rolled back), ⇡ Run all above (rebuilds the state a query needs), ↺ Original and ⧉ Scratchpad, and the tab has a ▶ Run all button. Setup code between sections appears as ⚙ setup cells |
| **Practice tab** | Write your answer, ▶ Run it, and ✔ **Check answer**. Your result set is compared with the official solution's: same columns and rows, and row order only matters when the solution sorts. You get the missing and unexpected rows plus the expected result. 💡 Solution reveals the answer. Attempts are saved in your browser |
| **Scratchpad** | A free SQL editor with history, a schema tree (click a column to insert it, ▶ to preview a table), run-selection and Explain |
| **Schema explorer** | The ER diagram and every table with its columns |
| **Docs** | Glossary, keyword index and tips, with working links |
| **Search** (`/`) | Find any query by ID, title, keyword or business question |
| **Progress** | Per-chapter progress bars in the sidebar and on the home page, stored in `localStorage` |
| **Editor** | CodeMirror with PostgreSQL highlighting. `Ctrl/Cmd+Enter` runs, `Ctrl+Space` autocompletes table and column names, `Ctrl+/` comments a line. Error lines are highlighted |
| **Themes** | Light and dark |

## How SQL is executed

- **One database session per browser tab**, like a psql window. `SET`, temp tables, prepared statements, `LISTEN`, dblink connections and psql variables persist between runs. The session chip in the top bar shows the backend pid; click it to reset the session.
- **Unchanged playbook cells run exactly as written.** The playbook files are designed to be safe and re-runnable.
- **Anything you write or edit runs in safe mode** (on by default). The whole script is wrapped in `BEGIN … ROLLBACK`, and its own `BEGIN`/`COMMIT`/`ROLLBACK` statements are ignored, so the data set never changes. Turn safe mode off (top bar) to keep your changes; `scripts/reset.sh` restores the data at any time. Statements that can't run inside a transaction (`VACUUM`, `CREATE INDEX CONCURRENTLY`…) need safe mode off.
- **psql meta-commands are emulated**: `\gset` (variables), `:var`, `:'var'`, `:"var"`, `\gexec`, `\crosstabview` (rendered as a pivot table), `\set`, `\unset` and `\echo`. Client-side file commands like `\copy` are skipped with a message.
- **Exercise checking** first recreates the state the exercise expects, by running the solutions file's setup plus all earlier solutions. It then runs the official solution and your query, each in a rolled-back transaction, and compares the last result sets. If the solution itself returns different values on every run (because of `now()`, `random()` or transaction ids), only the shape is graded: column count and row count.
- Results show at most 500 rows (`MAX_ROWS`), and statements time out after 60 s (`STATEMENT_TIMEOUT`). Long queries can be cancelled from the top bar.

> ⚠️ The app runs SQL as the `postgres` superuser. It's a **local learning tool**, so Docker binds it to `127.0.0.1` only. Don't expose it to a network.

## API (for the curious)

| Endpoint | Purpose |
|---|---|
| `GET /api/chapters`, `GET /api/chapters/:id` | chapter list / full chapter (README, cells, exercises + solutions) |
| `GET /api/index`, `GET /api/schema`, `GET /api/docs/:name`, `GET /api/file?path=` | search index, live schema, root docs, playbook files |
| `POST /api/run` `{sessionId, sql, safe, ref?}` | run a script (`ref` = `{chapter, cellId}`, so unchanged cells run as written) |
| `POST /api/explain` `{sessionId, sql}` | EXPLAIN ANALYZE of the last statement (rolled back) |
| `POST /api/exercise/run`, `POST /api/exercise/check` | run / grade an exercise attempt |
| `POST /api/cancel`, `POST /api/session/reset`, `GET /api/session/:id`, `GET /api/health` | session control and status |

## Tests
```bash
cd webapp
npm test                                   # unit tests: SQL splitter, variable substitution, transaction detection
node test/e2e.mjs http://localhost:3000    # runs EVERY cell of every chapter + grades EVERY exercise with its solution
```

## Code layout
```
server.js            Express server and API
lib/sqlsplit.js      psql-compatible statement splitter (quotes, $$ bodies, comments, BEGIN ATOMIC, meta-commands)
lib/playbook.js      parses chapters into cells / exercises / solutions
lib/runner.js        per-tab sessions, safe mode, psql meta emulation, result comparison
public/              single-page app (no build step): app.js + js/{util,results,markdown,chapter,pages}.js, style.css
Dockerfile           node:22-alpine image; used by the "web" service in ../docker-compose.yml
```
