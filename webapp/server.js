// ShopSphere SQL Playbook — interactive web app server.
//   npm start                (expects PostgreSQL on localhost:5432, see ../docker-compose.yml)
//   PORT, HOST, PG* env vars, PLAYBOOK_DIR override the defaults.
import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Playbook } from './lib/playbook.js';
import { SessionManager, adminQuery, loadTypeNames, gradedResult, compareResults, pgConfig } from './lib/runner.js';
import { splitSql } from './lib/sqlsplit.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const PLAYBOOK_DIR = path.resolve(process.env.PLAYBOOK_DIR || path.join(here, '..'));
const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '127.0.0.1';

const playbook = new Playbook(PLAYBOOK_DIR);
const sessions = new SessionManager();
const app = express();
app.use(express.json({ limit: '1mb' }));

// ---------- static files ----------
const nm = (p) => path.join(here, 'node_modules', p);
app.use('/vendor/codemirror', express.static(nm('codemirror')));
app.use('/vendor/marked', express.static(nm('marked/lib')));
app.use('/vendor/mermaid', express.static(nm('mermaid/dist')));
app.use(express.static(path.join(here, 'public')));

const wrap = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message, code: e.code });
  }
};

// ---------- content ----------
app.get('/api/chapters', wrap(async (req, res) => res.json(playbook.list())));

app.get('/api/chapters/:id', wrap(async (req, res) => {
  const ch = playbook.get(req.params.id);
  if (!ch) return res.status(404).json({ error: 'chapter not found' });
  res.json(ch);
}));

app.get('/api/index', wrap(async (req, res) => res.json(playbook.index())));

app.get('/api/docs/:name', wrap(async (req, res) => {
  const md = playbook.doc(req.params.name);
  if (md === null) return res.status(404).json({ error: 'doc not found' });
  res.type('text/markdown').send(md);
}));

app.get('/api/file', wrap(async (req, res) => {
  const text = playbook.file(String(req.query.path || ''));
  if (text === null) return res.status(404).json({ error: 'file not found' });
  res.type('text/plain').send(text);
}));

app.get('/api/schema', wrap(async (req, res) => {
  const r = await adminQuery(`
    SELECT c.table_schema, c.table_name, t.table_type, c.column_name, c.data_type, c.is_nullable
    FROM information_schema.columns c
    JOIN information_schema.tables t USING (table_schema, table_name)
    WHERE c.table_schema IN ('core', 'catalog', 'logistics', 'sales', 'audit', 'analytics', 'reporting', 'app')
      AND NOT (c.table_schema = 'analytics' AND c.table_name ~ '^events_')
    ORDER BY c.table_schema, c.table_name, c.ordinal_position`);
  const tables = new Map();
  for (const [schema, table, type, column, dataType, nullable] of r.rows) {
    const key = `${schema}.${table}`;
    if (!tables.has(key)) tables.set(key, { schema, table, type, columns: [] });
    tables.get(key).columns.push({ name: column, type: dataType, nullable: nullable === 'YES' });
  }
  res.json([...tables.values()]);
}));

app.get('/api/health', wrap(async (req, res) => {
  try {
    const r = await adminQuery(`SELECT version(), current_database(),
      (SELECT count(*) FROM sales.orders)::text AS orders`);
    const [version, db, orders] = r.rows[0];
    res.json({ ok: true, version, database: db, orders: Number(orders), host: pgConfig().host, port: pgConfig().port });
  } catch (e) {
    res.json({ ok: false, error: e.message, hint: 'Is the database running? Try: scripts/reset.sh' });
  }
}));

// ---------- execution ----------
/**
 * POST /api/run { sessionId, sql, safe, ref?: { chapter, cellId } }
 * A cell that is unchanged from the playbook runs exactly as written (trusted);
 * anything else honours the "safe" flag (wrap in a transaction that is rolled back).
 */
app.post('/api/run', wrap(async (req, res) => {
  const { sessionId, sql, safe = true, ref } = req.body || {};
  if (typeof sql !== 'string' || !sql.trim()) return res.status(400).json({ error: 'sql is required' });
  const session = sessions.get(sessionId);
  const original = ref ? playbook.cell(ref.chapter, ref.cellId) : null;
  const trusted = !!original && original.sql.trim() === sql.trim();
  const out = await session.enqueue(async () => {
    session.exerciseContext = null;
    return session.run(sql, { safe: trusted ? false : !!safe });
  });
  res.json({ ...out, trusted, pid: session.pid });
}));

/** POST /api/explain { sessionId, sql, analyze } — EXPLAIN the last statement, always rolled back. */
app.post('/api/explain', wrap(async (req, res) => {
  const { sessionId, sql, analyze = true } = req.body || {};
  const stmts = splitSql(sql || '').filter((i) => i.kind === 'sql');
  if (!stmts.length) return res.status(400).json({ error: 'nothing to explain' });
  const last = stmts[stmts.length - 1].text;
  const opts = analyze ? '(ANALYZE, BUFFERS, COSTS, VERBOSE OFF)' : '(COSTS)';
  const session = sessions.get(sessionId);
  const out = await session.enqueue(() => session.run(`EXPLAIN ${opts} ${last}`, { safe: true }));
  res.json({ ...out, explained: last });
}));

/**
 * POST /api/exercise/run   { sessionId, chapter, exerciseId, sql, safe }
 * POST /api/exercise/check { sessionId, chapter, exerciseId, sql }
 * Both first (re)create the state the exercise expects (solutions preamble + earlier solutions).
 */
async function ensureContext(session, chapter, exerciseId) {
  const ctx = playbook.exerciseContext(chapter, exerciseId);
  if (!ctx) throw Object.assign(new Error('exercise not found'), { status: 404 });
  const key = `${chapter}/${exerciseId}`;
  if (session.exerciseContext !== key && ctx.contextSql.trim()) {
    const prep = await session.run(ctx.contextSql, { safe: false });
    const err = prep.results.find((r) => r.error);
    if (err) throw Object.assign(new Error(`Preparing the exercise context failed: ${err.error.message}`), { status: 500 });
  }
  session.exerciseContext = key;
  return ctx;
}

app.post('/api/exercise/run', wrap(async (req, res) => {
  const { sessionId, chapter, exerciseId, sql, safe = true } = req.body || {};
  const session = sessions.get(sessionId);
  const out = await session.enqueue(async () => {
    await ensureContext(session, chapter, exerciseId);
    return session.run(sql || '', { safe: !!safe });
  });
  res.json({ ...out, pid: session.pid });
}));

app.post('/api/exercise/check', wrap(async (req, res) => {
  const { sessionId, chapter, exerciseId, sql } = req.body || {};
  if (typeof sql !== 'string' || !sql.trim()) return res.status(400).json({ error: 'write a query first' });
  const session = sessions.get(sessionId);
  const out = await session.enqueue(async () => {
    const ctx = await ensureContext(session, chapter, exerciseId);
    const expectedRun = await session.run(ctx.exercise.solution, { safe: true, keepAllRows: true });
    const actualRun = await session.run(sql, { safe: true, keepAllRows: true });
    const expected = gradedResult(expectedRun);
    const actual = gradedResult(actualRun);
    const attemptError = actualRun.results.find((r) => r.error);
    let verdict = attemptError
      ? { verdict: 'error', message: `Your query failed: ${attemptError.error.message}` }
      : compareResults(expected, actual, ctx.exercise.solution);
    if (verdict.verdict === 'wrong' && expected && actual) {
      // Volatile answers (now(), random(), xmin…) differ on every run: if the solution doesn't even
      // match itself, grade on shape instead (same columns and row count).
      const again = gradedResult(await session.run(ctx.exercise.solution, { safe: true, keepAllRows: true }));
      if (compareResults(expected, again, ctx.exercise.solution).verdict === 'wrong') {
        const sameShape = expected.fields.length === actual.fields.length && expected.totalRows === actual.totalRows;
        verdict = sameShape
          ? { verdict: 'correct', message: `Correct shape: ${actual.fields.length} column(s) × ${actual.totalRows} row(s). The values change on every run (time, random or transaction ids), so compare them with the expected output yourself.` }
          : { ...verdict, message: `${verdict.message} Note: this answer changes on every run, so only the shape (columns and row count) is graded.` };
      }
    }
    const slim = (r) => r && { fields: r.fields, rows: r.rows, totalRows: r.totalRows, truncated: r.truncated };
    for (const r of [...expectedRun.results, ...actualRun.results]) delete r.allRows;
    return { ...verdict, expected: slim(expected), actual: slim(actual), attempt: actualRun };
  });
  res.json(out);
}));

app.post('/api/cancel', wrap(async (req, res) => {
  const s = sessions.sessions.get(req.body?.sessionId);
  if (!s?.pid) return res.json({ cancelled: false });
  const r = await adminQuery('SELECT pg_cancel_backend($1)', [s.pid]);
  res.json({ cancelled: r.rows[0][0] === 't' });
}));

app.post('/api/session/reset', wrap(async (req, res) => {
  await sessions.reset(req.body?.sessionId);
  res.json({ ok: true });
}));

app.get('/api/session/:id', wrap(async (req, res) => {
  const s = sessions.sessions.get(req.params.id);
  res.json({ connected: !!s?.client, pid: s?.pid || null, vars: s?.vars || {}, busy: !!s?.busy });
}));

// SPA fallback
app.get(/^\/(?!api\/|vendor\/).*/, (req, res) => res.sendFile(path.join(here, 'public', 'index.html')));

loadTypeNames().catch((e) => console.warn('Could not load type names yet:', e.message));
app.listen(PORT, HOST, () => {
  console.log(`ShopSphere SQL Playbook web app → http://${HOST === '0.0.0.0' ? 'localhost' : HOST}:${PORT}`);
  console.log(`Playbook: ${PLAYBOOK_DIR}   Database: ${pgConfig().host}:${pgConfig().port}/${pgConfig().database}`);
});
