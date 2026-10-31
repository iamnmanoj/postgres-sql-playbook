// Rendering of query results (tables, plans, notices, errors) + the "run" helper.
import { h, api, state, setRunning, toast } from './util.js';

const NUMERIC = /^(smallint|integer|bigint|numeric|real|double precision|money|oid)/;

function cellNode(v, isNum) {
  if (v === null) return h('td', h('span.null', 'NULL'));
  return h(isNum ? 'td.num' : 'td', { title: v.length > 60 ? v : null }, v);
}

export function renderTable(r) {
  if (r.fields.length === 1 && r.fields[0].name === 'QUERY PLAN') {
    return h('pre.plan', r.rows.map((row) => row[0]).join('\n'));
  }
  if (r.crosstab) return renderCrosstab(r);
  const nums = r.fields.map((f) => NUMERIC.test(f.type));
  return h('div.table-wrap',
    h('table.grid-table',
      h('thead', h('tr', h('th', ''), r.fields.map((f) => h('th', f.name, h('small', f.type))))),
      h('tbody', r.rows.map((row, i) => h('tr', h('td.rownum', i + 1), row.map((v, j) => cellNode(v, nums[j])))))));
}

/** psql \crosstabview: column 1 = row header, column 2 = column header, column 3 = value */
function renderCrosstab(r) {
  if (r.fields.length < 3) return renderTable({ ...r, crosstab: false });
  const rowKeys = [];
  const colKeys = [];
  const map = new Map();
  for (const [a, b, v] of r.rows) {
    if (!rowKeys.includes(a)) rowKeys.push(a);
    if (!colKeys.includes(b)) colKeys.push(b);
    map.set(`${a}\u0000${b}`, v);
  }
  return h('div.table-wrap',
    h('table.grid-table',
      h('thead', h('tr', h('th', `${r.fields[0].name} \\ ${r.fields[1].name}`), colKeys.map((c) => h('th', c ?? 'NULL')))),
      h('tbody', rowKeys.map((rk) => h('tr', h('td', rk ?? 'NULL'),
        colKeys.map((ck) => cellNode(map.has(`${rk}\u0000${ck}`) ? map.get(`${rk}\u0000${ck}`) : null, true)))))));
}

function firstLine(sql) {
  const line = (sql || '').split('\n').find((l) => l.trim() && !l.trim().startsWith('--')) || '';
  return line.trim().slice(0, 110);
}

function errorBox(r) {
  const e = r.error;
  return h('div.res-error',
    h('b', 'ERROR: '), e.message,
    (e.detail || e.hint || e.where || e.code) && h('div.extra',
      [e.detail && `DETAIL: ${e.detail}`, e.hint && `HINT: ${e.hint}`, e.where && `CONTEXT: ${e.where}`, e.code && `SQLSTATE: ${e.code}`]
        .filter(Boolean).join('\n')));
}

/** Render a /api/run response into container; optionally highlight the error line in the editor. */
export function renderRun(container, resp, cm) {
  container.replaceChildren();
  if (cm) for (let i = 0; i < cm.lineCount(); i++) cm.removeLineClass(i, 'background', 'cm-error-line');

  const results = resp.results || [];
  const errors = results.filter((r) => r.error).length;
  const statements = results.filter((r) => !r.skipped).length;
  container.append(h('div.run-summary',
    h('span', `${statements} statement${statements === 1 ? '' : 's'} · ${resp.durationMs ?? '?'} ms`),
    resp.trusted ? h('span.pill', { title: 'Unchanged playbook query: ran exactly as written' }, 'ran as written')
      : resp.rolledBack ? h('span.pill.safe', { title: 'Safe mode: everything was rolled back' }, '↺ rolled back (safe mode)')
        : h('span.pill.live', { title: 'Changes were kept' }, '● changes kept'),
    errors ? h('span.pill', { style: { color: 'var(--err)' } }, `${errors} error`) : null));

  const compact = results.length > 1;
  for (const r of results) {
    if (r.skipped) {
      container.append(h(r.unsupported ? 'div.res-skip' : 'div.res-skip.info', r.message));
      continue;
    }
    const box = h('div.res');
    const hasRows = r.fields && r.fields.length;
    if (compact || hasRows || r.error) {
      box.append(h('div.res-head',
        h('span.cmd', r.error ? 'ERROR' : r.command || ''),
        !r.error && hasRows ? h('span', `${r.totalRows} row${r.totalRows === 1 ? '' : 's'}`) : null,
        !r.error && !hasRows && r.rowCount !== null && r.rowCount !== undefined && r.command !== 'SELECT' ? h('span', `${r.rowCount}`) : null,
        h('span', `${r.durationMs} ms`),
        h('span.stmt', { title: r.statement }, firstLine(r.statement))));
    } else {
      box.append(h('div.res-line', h('b', r.command || 'OK'), r.rowCount ? ` ${r.rowCount}` : '', ` · ${r.durationMs} ms`));
    }
    for (const n of r.notices || []) box.append(h('div.notice', n));
    if (r.message) box.append(h('div.notice', r.message));
    if (r.error) {
      box.append(errorBox(r));
      if (cm && r.offset !== undefined) {
        const pos = r.offset + Math.max(0, (r.error.position || 1) - 1);
        const line = cm.posFromIndex(Math.min(pos, cm.getValue().length)).line;
        cm.addLineClass(line, 'background', 'cm-error-line');
      }
    } else if (hasRows) {
      box.append(renderTable(r));
      if (r.truncated) box.append(h('div.trunc', `Showing the first ${r.rows.length} of ${r.totalRows} rows.`));
      if (r.totalRows === 0) box.append(h('div.res-line', '(0 rows)'));
    }
    container.append(box);
  }
}

/**
 * Execute SQL via the API with running indicator. kind: 'cell' | 'exercise' | 'explain' | 'scratch'
 * Returns the response (or null on transport errors).
 */
export async function execute(endpoint, body, label = 'Running…') {
  setRunning(1, label);
  try {
    return await api(endpoint, { sessionId: state.sessionId, safe: state.safe, ...body });
  } catch (e) {
    toast(e.message, 'err');
    return null;
  } finally {
    setRunning(-1);
    document.dispatchEvent(new Event('session-changed'));
  }
}

export const hasError = (resp) => !resp || (resp.results || []).some((r) => r.error);
