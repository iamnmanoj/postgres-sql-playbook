// Home, scratchpad, schema explorer, docs and file viewer pages.
import { h, api, state, progress, makeEditor, chapterRoute, getChapter, toast } from './util.js';
import { renderRun, execute } from './results.js';
import { renderMarkdown, renderMermaid } from './markdown.js';
import { openScratch } from './chapter.js';

// ------------------------------------------------------------------ home
export async function homeView(main) {
  const totals = state.chapters.reduce((a, c) => ({ q: a.q + c.queryCount, e: a.e + c.exerciseCount }), { q: 0, e: 0 });
  const doneQ = Object.keys(progress.data.queries).length;
  const doneE = Object.values(progress.data.exercises).filter((v) => v === 'correct').length;
  const pct = (a, b) => (b ? Math.round((100 * a) / b) : 0);
  const health = h('div');

  const byCat = new Map();
  for (const c of state.chapters) {
    if (!byCat.has(c.category)) byCat.set(c.category, []);
    byCat.get(c.category).push(c);
  }
  const next = state.chapters.find((c) => c.queryCount && progress.chapterStats(c).done < progress.chapterStats(c).total);

  main.replaceChildren(h('div.page',
    health,
    h('div.hero',
      h('div.card',
        h('div.eyebrow', 'PostgreSQL 17 · hands-on'),
        h('h1', 'Learn PostgreSQL by building ShopSphere'),
        h('p.muted', 'A multi-seller e-commerce marketplace with 33 tables and ~740k realistic rows. Read each lesson, run every query against the live database, then practise with exercises that are checked automatically.'),
        h('div', { style: { display: 'flex', gap: '10px', flexWrap: 'wrap' } },
          progress.data.last ? h('a.btn.btn-primary', { href: progress.data.last }, '⏵ Continue where you left off') : null,
          next ? h(`a.btn${progress.data.last ? '' : '.btn-primary'}`, { href: chapterRoute(next.id) }, `Next up: ${next.id} · ${next.shortTitle}`) : null,
          h('a.btn', { href: '#/scratch' }, '🧪 Open the scratchpad'))),
      h('div.card.stats',
        h('div.stat', h('span.muted', 'Queries run'), h('b', `${doneQ} / ${totals.q}`), h('div.progress', h('span', { style: { width: pct(doneQ, totals.q) + '%' } }))),
        h('div.stat', h('span.muted', 'Exercises solved'), h('b', `${doneE} / ${totals.e}`), h('div.progress', h('span', { style: { width: pct(doneE, totals.e) + '%' } }))),
        h('div.stat', { style: { gridColumn: '1 / -1' } }, h('span.muted', 'Overall'), h('div.progress', h('span', { style: { width: pct(doneQ + doneE, totals.q + totals.e) + '%' } }))))),
    h('div.howto',
      h('div.card', h('h4', '📘 Lesson → ▶ Queries → 🏋️ Practice'), h('p', 'Every chapter has the same three tabs. Queries are notebook cells: run them, edit them, break them.')),
      h('div.card', h('h4', '🛡️ Safe mode'), h('p', 'On by default: anything you write or edit runs inside a transaction that is rolled back, so the data set never changes. Unchanged playbook queries always run exactly as written.')),
      h('div.card', h('h4', '🧵 Your own session'), h('p', 'This tab has its own database session, like a psql window: SET, temp tables and \\gset variables persist. Reset it from the session chip in the top bar.')),
      h('div.card', h('h4', '⌨️ Shortcuts'), h('p', h('kbd', 'Ctrl'), '+', h('kbd', 'Enter'), ' run · ', h('kbd', 'Ctrl'), '+', h('kbd', 'Space'), ' autocomplete · ', h('kbd', 'Ctrl'), '+', h('kbd', '/'), ' comment · ', h('kbd', '/'), ' search'))),
    [...byCat.entries()].map(([cat, list]) => [
      h('div.cat-title', cat),
      h('div.grid', list.map((c) => {
        const s = progress.chapterStats(c);
        return h('a.card.ch-card', { href: chapterRoute(c.id) },
          h('div.eyebrow', `Chapter ${c.id}`),
          h('h3', c.shortTitle.replace(/`/g, '')),
          s.total ? h('div.progress', h('span', { style: { width: pct(s.done, s.total) + '%' } })) : null,
          h('div.meta', h('span', c.queryCount ? `${c.queryCount} queries · ${c.exerciseCount} exercises` : 'Setup guide'), s.total ? h('span', `${pct(s.done, s.total)}%`) : null));
      })),
    ])));

  try {
    const hc = await api('/api/health');
    if (!hc.ok) health.replaceChildren(h('div.db-down', h('b', '⚠ Database not reachable: '), hc.error, h('div.muted', hc.hint)));
  } catch { /* ignore */ }
}

// ------------------------------------------------------------------ schema tree (shared)
function schemaTree(onPick) {
  const filter = h('input', { type: 'search', placeholder: 'Filter tables / columns…' });
  const list = h('div');
  const render = () => {
    const q = filter.value.toLowerCase();
    const bySchema = new Map();
    for (const t of state.schema || []) {
      const match = !q || `${t.schema}.${t.table}`.includes(q) || t.columns.some((c) => c.name.includes(q));
      if (!match) continue;
      if (!bySchema.has(t.schema)) bySchema.set(t.schema, []);
      bySchema.get(t.schema).push(t);
    }
    list.replaceChildren(...[...bySchema.entries()].map(([schema, tables]) =>
      h('details', { open: q || schema === 'sales' ? true : null },
        h('summary', h('b', schema), h('span.muted', ` (${tables.length})`)),
        tables.map((t) => h('details', { open: q && t.columns.some((c) => c.name.includes(q)) ? true : null },
          h('summary.tbl', { title: 'Click the name to expand; double-click to insert' , ondblclick: () => onPick(`${t.schema}.${t.table}`) },
            t.table, t.type === 'VIEW' ? h('span.muted', ' (view)') : null),
          h('div.cols',
            h('div', { onclick: () => onPick(`SELECT * FROM ${t.schema}.${t.table} LIMIT 20;`, true) }, h('span', '▶ preview 20 rows')),
            t.columns.map((c) => h('div', { onclick: () => onPick(c.name), title: 'insert column name' },
              h('span', c.name), h('span.ttype', c.type.replace('timestamp with time zone', 'timestamptz').replace('character varying', 'varchar'))))))))));
  };
  filter.addEventListener('input', render);
  if (state.schema) render();
  else { list.append(h('p.muted', 'Loading schema…')); Promise.resolve(state.schemaReady).then(render); }
  return h('div.card.schema-tree', filter, list);
}

// ------------------------------------------------------------------ scratchpad
export function scratchView(main) {
  const results = h('div.results');
  const editorDiv = h('div.editor');
  const historyList = h('div');
  const history = () => JSON.parse(localStorage.getItem('pb.history') || '[]');
  let cm;

  const renderHistory = () => historyList.replaceChildren(...history().map((item) =>
    h('div.history-item', { title: item.sql, onclick: () => cm.setValue(item.sql) },
      item.ok ? '✓ ' : '✗ ', item.sql.replace(/\s+/g, ' ').slice(0, 140))));

  const run = async () => {
    const sql = cm.getSelection() || cm.getValue();
    const resp = await execute('/api/run', { sql }, 'Running scratchpad…');
    if (!resp) return;
    renderRun(results, resp, cm.getSelection() ? null : cm);
    const ok = !resp.results.some((r) => r.error);
    const hist = [{ sql, ok, ts: Date.now() }, ...history().filter((x) => x.sql !== sql)].slice(0, 25);
    localStorage.setItem('pb.history', JSON.stringify(hist));
    renderHistory();
  };
  const explain = async () => {
    const resp = await execute('/api/explain', { sql: cm.getSelection() || cm.getValue() }, 'EXPLAIN…');
    if (resp) renderRun(results, resp, null);
  };

  const left = h('div',
    h('div.card', { style: { padding: '0', overflow: 'hidden' } },
      editorDiv,
      h('div.cell-actions',
        h('button.btn.btn-primary.btn-small', { onclick: run, title: 'Ctrl/Cmd + Enter (runs the selection if any)' }, '▶ Run'),
        h('button.btn.btn-small', { onclick: explain }, '🔍 Explain analyze'),
        h('button.btn.btn-small.btn-ghost', { onclick: () => { cm.setValue(''); results.replaceChildren(); } }, 'Clear'),
        h('span.mode-tag', 'Tip: select part of the script to run only that part.')),
      results),
    h('div.history', h('div.cat-title', 'History'), historyList));

  main.replaceChildren(h('div.page',
    h('div.page-head', h('div.eyebrow', 'Free practice'), h('h1', '🧪 Scratchpad'),
      h('p.muted', 'Write any SQL against the ShopSphere database. Safe mode (top right) decides whether changes are rolled back. Double-click a table to insert its name, click a column to insert it.')),
    h('div.split', left, schemaTree((text, replace) => {
      if (replace) { cm.setValue(text); run(); } else { cm.replaceSelection(text); cm.focus(); }
    }))));

  cm = makeEditor(editorDiv, localStorage.getItem('pb.scratch') || '-- Try anything, e.g.\nSELECT status, count(*) FROM sales.orders GROUP BY status ORDER BY 2 DESC;', {
    onRun: run, tall: true,
    onChange: (v) => localStorage.setItem('pb.scratch', v),
  });
  cm.refresh();
  cm.focus();
  renderHistory();
}

// ------------------------------------------------------------------ schema explorer
export async function schemaView(main) {
  await state.schemaReady;
  const ch01 = await getChapter('01');
  const er = /```mermaid\n([\s\S]*?)```/.exec(ch01.readme)?.[1] || '';
  const filter = h('input', { type: 'search', placeholder: 'Filter tables or columns…', style: { padding: '7px 10px', borderRadius: '8px', border: '1px solid var(--border)', background: 'var(--panel)', color: 'var(--text)', width: '320px' } });
  const grid = h('div.schema-tables');
  const render = () => {
    const q = filter.value.toLowerCase();
    grid.replaceChildren(...(state.schema || [])
      .filter((t) => ['core', 'catalog', 'logistics', 'sales', 'audit', 'analytics'].includes(t.schema))
      .filter((t) => !q || `${t.schema}.${t.table}`.includes(q) || t.columns.some((c) => c.name.includes(q)))
      .map((t) => h('div.card',
        h('h4', h('span.muted', t.schema + '.'), t.table,
          h('button.btn.btn-small.btn-ghost', { style: { float: 'right' }, onclick: () => openScratch(`SELECT * FROM ${t.schema}.${t.table} LIMIT 20;`) }, '▶')),
        h('table', t.columns.map((c) => h('tr', h('td', c.name, c.nullable ? '' : h('span.muted', ' •')), h('td', c.type.replace('timestamp with time zone', 'timestamptz'))))))));
  };
  filter.addEventListener('input', render);
  const diagram = h('div.mermaid', er);
  main.replaceChildren(h('div.page',
    h('div.page-head', h('div.eyebrow', 'Data model'), h('h1', '🗺️ ShopSphere schema'),
      h('p.muted', 'The entity-relationship diagram and every table with its columns (• = NOT NULL). Full DDL: ',
        h('a', { href: '#/file/chapters/01_ddl_schema/schema.sql' }, 'schema.sql'), ' · design notes: ',
        h('a', { href: '#/chapter/01/lesson/#the-shopsphere-data-model' }, 'chapter 01'), '.')),
    h('div.card', { style: { marginBottom: '20px' } }, diagram),
    h('div', { style: { margin: '10px 0' } }, filter),
    grid));
  render();
  await renderMermaid(main);
}

// ------------------------------------------------------------------ docs & files
export async function docView(main, name, anchor) {
  const md = await api(`/api/docs/${name}`);
  const body = renderMarkdown(md, `${name}.md`, { onTry: openScratch });
  main.replaceChildren(h('div.page', h('div.card', body)));
  await renderMermaid(main);
  if (anchor) main.querySelector(`#${CSS.escape(anchor)}`)?.scrollIntoView({ block: 'start' });
}

export async function fileView(main, path) {
  let text;
  try { text = await api(`/api/file?path=${encodeURIComponent(path)}`); } catch (e) { toast(e.message, 'err'); return; }
  const ed = h('div.editor');
  main.replaceChildren(h('div.page',
    h('div.page-head', h('div.eyebrow', 'Playbook file'), h('h1', { style: { fontFamily: 'var(--mono)', fontSize: '20px' } }, path),
      path.endsWith('.sql') ? h('button.btn.btn-small', { onclick: () => openScratch(text) }, '⧉ Open in scratchpad') : null),
    h('div.card', { style: { padding: 0, overflow: 'hidden' } }, ed)));
  const cm = makeEditor(ed, text, { readOnly: true });
  if (!path.endsWith('.sql')) cm.setOption('mode', 'text/plain');
  cm.refresh();
}

export async function mdFileView(main, path) {
  let md;
  try { md = await api(`/api/file?path=${encodeURIComponent(path)}`); } catch (e) { toast(e.message, 'err'); return; }
  main.replaceChildren(h('div.page', h('div.card', renderMarkdown(md, path, { onTry: openScratch }))));
  await renderMermaid(main);
}
