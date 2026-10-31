// Executes SQL for the web app.
// Each browser tab gets its own persistent PostgreSQL session (like a psql window), so
// SET, temp tables, prepared statements, dblink connections and \gset variables persist.
import pg from 'pg';
import { splitSql, substituteVars, transactionControl, stripComments } from './sqlsplit.js';

const MAX_ROWS = Number(process.env.MAX_ROWS || 500);
const STATEMENT_TIMEOUT = process.env.STATEMENT_TIMEOUT || '60s';
const SESSION_IDLE_MS = 30 * 60 * 1000;

// Return every value as PostgreSQL's own text representation (exactly what psql shows)
const rawTypes = { getTypeParser: () => (v) => v };

export function pgConfig() {
  return {
    host: process.env.PGHOST || 'localhost',
    port: Number(process.env.PGPORT || 5432),
    user: process.env.PGUSER || 'postgres',
    password: process.env.PGPASSWORD || 'postgres',
    database: process.env.PGDATABASE || 'shopsphere',
  };
}

let typeNames = new Map();
export async function loadTypeNames() {
  const r = await adminQuery('SELECT oid::int, format_type(oid, NULL) FROM pg_type');
  typeNames = new Map(r.rows.map(([oid, name]) => [Number(oid), name]));
}

/** One-off query on a short-lived connection (schema browser, health, cancel). */
export async function adminQuery(text, params = []) {
  const c = new pg.Client({ ...pgConfig(), types: rawTypes });
  await c.connect();
  try {
    return await c.query({ text, values: params, rowMode: 'array' });
  } finally {
    await c.end();
  }
}

const errorInfo = (e) => ({
  message: e.message, code: e.code, detail: e.detail, hint: e.hint,
  position: e.position ? Number(e.position) : undefined, where: e.where, severity: e.severity,
});

export class Session {
  constructor(id) {
    this.id = id;
    this.client = null;
    this.vars = {};
    this.pid = null;
    this.lastUsed = Date.now();
    this.queue = Promise.resolve();
    this.notices = [];
    this.exerciseContext = null;   // key of the exercise context currently loaded
    this.busy = false;
  }

  async connect() {
    if (this.client) return;
    if (typeNames.size === 0) await loadTypeNames().catch(() => {});
    const client = new pg.Client({ ...pgConfig(), types: rawTypes, application_name: 'playbook-web' });
    client.on('notice', (m) => this.notices.push(`${m.severity || 'NOTICE'}: ${m.message}${m.detail ? `\nDETAIL: ${m.detail}` : ''}`));
    client.on('notification', (n) => this.notices.push(`Asynchronous notification "${n.channel}" with payload "${n.payload}" received from server process with PID ${n.processId}.`));
    client.on('error', () => { this.client = null; });
    client.on('end', () => { if (this.client === client) this.client = null; });
    await client.connect();
    this.client = client;
    await client.query(`SET statement_timeout = '${STATEMENT_TIMEOUT}'`);
    const r = await client.query({ text: 'SELECT pg_backend_pid()', rowMode: 'array' });
    this.pid = Number(r.rows[0][0]);
  }

  async close() {
    const c = this.client;
    this.client = null;
    this.vars = {};
    this.exerciseContext = null;
    if (c) await c.end().catch(() => {});
  }

  /** Serialise work on this session (one statement stream at a time, like psql). */
  enqueue(fn) {
    this.lastUsed = Date.now();
    const job = this.queue.then(async () => {
      this.busy = true;
      try { await this.connect(); return await fn(); } finally { this.busy = false; this.lastUsed = Date.now(); }
    });
    this.queue = job.catch(() => {});
    return job;
  }

  takeNotices() {
    const n = this.notices;
    this.notices = [];
    return n;
  }

  async execStatement(text, offset) {
    const sql = substituteVars(text, this.vars);
    const t0 = performance.now();
    try {
      const res = await this.client.query({ text: sql, rowMode: 'array' });
      const results = Array.isArray(res) ? res : [res];
      return results.map((r) => ({
        statement: text, offset,
        command: r.command, rowCount: r.rowCount,
        fields: (r.fields || []).map((f) => ({ name: f.name, type: typeNames.get(f.dataTypeID) || String(f.dataTypeID) })),
        rows: (r.rows || []).slice(0, MAX_ROWS),
        totalRows: (r.rows || []).length,
        truncated: (r.rows || []).length > MAX_ROWS,
        allRows: r.rows || [],
        durationMs: Math.round((performance.now() - t0) * 10) / 10,
        notices: this.takeNotices(),
      }));
    } catch (e) {
      return [{ statement: text, offset, error: errorInfo(e), durationMs: Math.round(performance.now() - t0), notices: this.takeNotices() }];
    }
  }

  async inFailedTransaction() {
    try { await this.client.query('SELECT 1'); return false; } catch (e) { return e.code === '25P02'; }
  }

  /**
   * Run a script.
   *  safe = true  → wrap in BEGIN … ROLLBACK and ignore the script's own transaction control.
   *  safe = false → run exactly as written (like psql).
   * Returns { results: [...], rolledBack, durationMs, vars }
   */
  async run(script, { safe = true, keepAllRows = false } = {}) {
    const items = splitSql(script);
    const results = [];
    const t0 = performance.now();
    let failed = false;
    this.takeNotices();
    if (safe) await this.client.query('BEGIN');

    for (const item of items) {
      if (item.kind === 'meta') {
        results.push(this.runMeta(item));
        continue;
      }
      const tc = transactionControl(item.text);
      if (safe && tc) {
        results.push({ statement: item.text, offset: item.start, skipped: true,
          message: `${stripComments(item.text).trim().split(/\s+/)[0].toUpperCase()} ignored — safe mode keeps everything in one transaction that is rolled back.` });
        continue;
      }
      const out = await this.execStatement(item.text, item.start);
      if (item.meta) await this.applyMeta(item.meta, out, results);
      else results.push(...out);
      if (out.some((r) => r.error)) { failed = true; break; }
    }

    if (safe) {
      await this.client.query('ROLLBACK').catch(() => {});
    } else if (failed && (await this.inFailedTransaction())) {
      await this.client.query('ROLLBACK').catch(() => {});
      results.push({ skipped: true, message: 'The open transaction was aborted by the error and has been rolled back.' });
    }
    const late = this.takeNotices();
    if (late.length && results.length) (results[results.length - 1].notices ||= []).push(...late);
    if (!keepAllRows) for (const r of results) delete r.allRows;
    return { results, rolledBack: safe, durationMs: Math.round(performance.now() - t0), vars: { ...this.vars } };
  }

  /** Statement terminated by \gset, \gexec or \crosstabview. */
  async applyMeta(meta, out, results) {
    const r = out[out.length - 1];
    if (r.error) { results.push(...out); return; }
    if (meta.cmd === 'gset') {
      if (r.totalRows !== 1) {
        results.push({ ...r, error: { message: `\\gset: query returned ${r.totalRows} rows, expected exactly 1` } });
        return;
      }
      const prefix = meta.args.trim();
      const set = [];
      r.fields.forEach((f, i) => {
        const v = r.allRows[0][i];
        if (v === null) delete this.vars[prefix + f.name];
        else this.vars[prefix + f.name] = v;
        set.push(`${prefix}${f.name} = ${v === null ? '(unset)' : v}`);
      });
      results.push({ ...r, rows: [], fields: [], gset: set, message: `\\gset stored: ${set.join(', ')}` });
    } else if (meta.cmd === 'gexec') {
      results.push({ ...r, message: '\\gexec: executing each value as a statement' });
      for (const row of r.allRows) {
        for (const v of row) {
          if (v === null) continue;
          const sub = await this.execStatement(v, r.offset);
          results.push(...sub);
          if (sub.some((x) => x.error)) return;
        }
      }
    } else if (meta.cmd === 'crosstabview') {
      results.push({ ...r, crosstab: true });
    } else {
      results.push(...out);
    }
  }

  /** Stand-alone psql meta-commands. */
  runMeta(item) {
    const { cmd, args } = item;
    if (cmd === 'set') {
      const [name, ...rest] = args.split(/\s+/);
      if (name) this.vars[name] = rest.join(' ').replace(/^'(.*)'$/, '$1');
      return { skipped: true, offset: item.start, message: `\\set ${name}` };
    }
    if (cmd === 'unset') { delete this.vars[args.trim()]; return { skipped: true, offset: item.start, message: `\\unset ${args}` }; }
    if (cmd === 'echo' || cmd === 'qecho') return { skipped: true, offset: item.start, message: args };
    return {
      skipped: true, offset: item.start, unsupported: true,
      message: `psql meta-command \\${cmd} isn't available in the web app — run it in a terminal with scripts/psql.sh.`,
    };
  }
}

export class SessionManager {
  constructor() {
    this.sessions = new Map();
    setInterval(() => this.reap(), 60 * 1000).unref();
  }

  get(id) {
    if (!/^[A-Za-z0-9_-]{8,64}$/.test(id || '')) throw Object.assign(new Error('invalid session id'), { status: 400 });
    let s = this.sessions.get(id);
    if (!s) { s = new Session(id); this.sessions.set(id, s); }
    return s;
  }

  async reset(id) {
    const s = this.sessions.get(id);
    if (s) { await s.close(); this.sessions.delete(id); }
  }

  reap() {
    const now = Date.now();
    for (const [id, s] of this.sessions) {
      if (!s.busy && now - s.lastUsed > SESSION_IDLE_MS) { s.close(); this.sessions.delete(id); }
    }
  }
}

/** Pick the result set to grade: the last successful statement that returned columns. */
export function gradedResult(run) {
  const withRows = run.results.filter((r) => !r.error && r.fields && r.fields.length);
  return withRows[withRows.length - 1] || null;
}

/** Compare an attempt with the expected result. */
export function compareResults(expected, actual, expectedSql = '') {
  if (!expected) return { verdict: 'manual', message: 'This exercise has no result set to compare (e.g. DDL). Compare your work with the solution.' };
  if (!actual) return { verdict: 'wrong', message: 'Your query did not return a result set.' };
  const ec = expected.fields.length;
  const ac = actual.fields.length;
  if (ec !== ac) return { verdict: 'wrong', message: `Expected ${ec} column(s) (${expected.fields.map((f) => f.name).join(', ')}), got ${ac}.` };
  const er = expected.allRows || expected.rows;
  const ar = actual.allRows || actual.rows;
  const key = (row) => JSON.stringify(row);
  if (er.length === ar.length && er.every((row, i) => key(row) === key(ar[i]))) {
    return { verdict: 'correct', message: `Correct! ${er.length} row(s) match exactly.` };
  }
  const count = new Map();
  for (const row of er) count.set(key(row), (count.get(key(row)) || 0) + 1);
  const extra = [];
  for (const row of ar) {
    const k = key(row);
    if (count.get(k)) count.set(k, count.get(k) - 1);
    else extra.push(row);
  }
  const missing = [];
  for (const [k, n] of count) for (let i = 0; i < n; i++) missing.push(JSON.parse(k));
  if (!missing.length && !extra.length) {
    const ordered = /\border\s+by\b/i.test(stripComments(expectedSql).split(';').filter((s) => s.trim()).pop() || '');
    return ordered
      ? { verdict: 'order', message: 'All the right rows, but in a different order. Check your ORDER BY.' }
      : { verdict: 'correct', message: `Correct! ${er.length} row(s) match (order doesn't matter here).` };
  }
  return {
    verdict: 'wrong',
    message: `Expected ${er.length} row(s), got ${ar.length}. ${missing.length} expected row(s) missing, ${extra.length} unexpected row(s).`
      + (/(now|random|clock_timestamp|gen_random_uuid)\s*\(/i.test(expectedSql) ? ' (This exercise uses time/random functions, so small differences are expected.)' : ''),
    missing: missing.slice(0, 5),
    extra: extra.slice(0, 5),
  };
}
