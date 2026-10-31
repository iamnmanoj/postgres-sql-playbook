// Chapter page: Lesson (README) / Queries (notebook cells) / Practice (exercises).
import { h, $, api, state, progress, toast, makeEditor, chapterRoute, getChapter } from './util.js';
import { renderRun, renderTable, execute, hasError } from './results.js';
import { renderMarkdown, renderMermaid } from './markdown.js';

export function openScratch(sql) {
  localStorage.setItem('pb.scratch', sql);
  location.hash = '#/scratch';
}

function chapterHeader(ch, meta, tab) {
  const stats = progress.chapterStats(meta);
  const pct = stats.total ? Math.round((100 * stats.done) / stats.total) : 0;
  const tabLink = (t, label, count) => h(`a${tab === t ? '.active' : ''}`, { href: chapterRoute(ch.id, t) }, label, count !== undefined ? h('span.count', count) : null);
  const prev = state.chapters[state.chapters.findIndex((c) => c.id === ch.id) - 1];
  const next = state.chapters[state.chapters.findIndex((c) => c.id === ch.id) + 1];
  return h('div',
    h('div.page-head',
      h('div.eyebrow', `Chapter ${ch.id} · `, h('span.badge.cat', ch.category)),
      h('h1', ch.shortTitle.replace(/`/g, '')),
      stats.total ? h('div', { style: { display: 'flex', gap: '12px', alignItems: 'center' } },
        h('div.progress', { style: { flex: '1', maxWidth: '360px' } }, h('span', { style: { width: pct + '%' } })),
        h('span.muted', { style: { fontSize: '13px' } }, `${stats.q}/${meta.queryCount} queries run · ${stats.e}/${meta.exerciseCount} exercises solved`)) : null),
    h('nav.tabs',
      tabLink('lesson', '📘 Lesson'),
      ch.cells.length ? tabLink('queries', '▶ Queries', meta.queryCount) : null,
      ch.exercises.length ? tabLink('practice', '🏋️ Practice', meta.exerciseCount) : null,
      h('div.tab-actions',
        prev ? h('a.btn.btn-small', { href: chapterRoute(prev.id) }, '← ', prev.id) : null,
        next ? h('a.btn.btn-small', { href: chapterRoute(next.id) }, next.id, ' →') : null)));
}

// ------------------------------------------------------------------ lesson
function lessonTab(ch) {
  const md = renderMarkdown(ch.readme, `chapters/${ch.dir}/README.md`, { onTry: openScratch });
  // drop the duplicated H1 and the prev/next line (we have our own header)
  md.querySelector('h1')?.remove();
  const nav = md.querySelector('p');
  if (nav && /Previous|Next|Index/.test(nav.textContent) && nav.textContent.length < 120) nav.remove();
  const cta = h('div', { style: { display: 'flex', gap: '10px', margin: '28px 0' } },
    ch.cells.length ? h('a.btn.btn-primary', { href: chapterRoute(ch.id, 'queries') }, '▶ Run the queries') : null,
    ch.exercises.length ? h('a.btn', { href: chapterRoute(ch.id, 'practice') }, '🏋️ Practice') : null);
  return h('div', h('div.card', md), cta);
}

// ------------------------------------------------------------------ queries
function cellView(ch, cell, controller) {
  const isQuery = cell.type === 'query';
  const results = h('div.results');
  const status = h('span.status');
  const modeTag = h('span.mode-tag');
  const doneBadge = h('span.badge.done' + (progress.queryDone(cell.id) ? '' : '.hidden'), '✓ done');
  const editorDiv = h('div.editor');
  let cm;

  const updateMode = () => {
    const edited = cm.getValue().trim() !== cell.sql.trim();
    modeTag.className = 'mode-tag' + (edited ? ' edited' : '');
    modeTag.textContent = edited
      ? (state.safe ? '✎ edited · runs in safe mode (rolled back)' : '✎ edited · changes will be kept')
      : 'runs exactly as written';
    resetBtn.classList.toggle('hidden', !edited);
  };

  const run = async () => {
    const t0 = performance.now();
    const resp = await execute('/api/run', { sql: cm.getValue(), ref: { chapter: ch.id, cellId: cell.id } }, `Running ${isQuery ? cell.id : 'setup'}…`);
    if (!resp) return false;
    renderRun(results, resp, cm);
    const ok = !hasError(resp);
    status.textContent = ok ? `✓ ${new Date().toLocaleTimeString()}` : '✗ failed';
    status.style.color = ok ? 'var(--ok)' : 'var(--err)';
    if (ok && isQuery) { progress.markQuery(cell.id); doneBadge.classList.remove('hidden'); }
    void t0;
    return ok;
  };

  const explain = async () => {
    const resp = await execute('/api/explain', { sql: cm.getValue() }, `EXPLAIN ${cell.id}…`);
    if (resp) renderRun(results, resp, cm);
  };

  const resetBtn = h('button.btn.btn-small.btn-ghost.hidden', { onclick: () => { cm.setValue(cell.sql); results.replaceChildren(); } }, '↺ Original');
  const el = h(`div.cell${isQuery ? '' : '.setup'}`, { id: `cell-${cell.id}` },
    h('div.cell-head',
      isQuery ? h('span.cell-id', cell.id) : h('span.cell-id', '⚙'),
      h('span.cell-title', cell.title),
      doneBadge),
    h('div.cell-meta',
      isQuery && cell.question ? h('div.question', cell.question) : null,
      !isQuery ? h('div.notes', 'Setup code for the queries below. "Run all" includes it; run it first if a query complains that something does not exist.') : null,
      ...(cell.notes || []).map((n) => h('div.notes', n)),
      cell.keywords?.length ? h('div.kw', cell.keywords.map((k) => h('span', k))) : null),
    editorDiv,
    h('div.cell-actions',
      h('button.btn.btn-primary.btn-small', { onclick: run, title: 'Ctrl/Cmd + Enter' }, '▶ Run'),
      isQuery ? h('button.btn.btn-small', { onclick: explain, title: 'EXPLAIN ANALYZE the last statement (rolled back)' }, '🔍 Explain') : null,
      h('button.btn.btn-small', { onclick: () => controller.runUpTo(cell.id), title: 'Run every cell above this one (to recreate the state it needs)' }, '⇡ Run all above'),
      h('button.btn.btn-small.btn-ghost', { onclick: () => openScratch(cm.getValue()), title: 'Copy into the scratchpad' }, '⧉ Scratchpad'),
      resetBtn, modeTag, status),
    results);

  cm = makeEditor(editorDiv, cell.sql, { onRun: run, onChange: updateMode });
  updateMode();
  return { el, run, cm, cell };
}

function queriesTab(ch, anchor) {
  const wrap = h('div');
  const views = [];
  const controller = {
    async runRange(endIdx, label) {
      for (let i = 0; i < endIdx; i++) {
        runAllBtn.textContent = `${label} ${i + 1}/${endIdx}…`;
        const ok = await views[i].run();
        if (!ok) {
          views[i].el.scrollIntoView({ behavior: 'smooth', block: 'center' });
          toast(`Stopped at ${views[i].cell.id}: it returned an error`, 'err');
          runAllBtn.textContent = '▶ Run all';
          return false;
        }
      }
      runAllBtn.textContent = '▶ Run all';
      return true;
    },
    async runUpTo(cellId) {
      const idx = views.findIndex((v) => v.cell.id === cellId);
      if (idx <= 0) { toast('Nothing above this cell'); return; }
      if (await this.runRange(idx, '⇡ Running')) toast(`Ran ${idx} cell(s) above ${cellId}`, 'ok');
    },
  };
  const runAllBtn = h('button.btn.btn-primary.btn-small', {
    onclick: async () => { if (await controller.runRange(views.length, '▶ Running')) toast('All cells ran successfully 🎉', 'ok'); },
  }, '▶ Run all');

  wrap.append(h('div.card', { style: { marginBottom: '18px', display: 'flex', gap: '14px', alignItems: 'center', flexWrap: 'wrap' } },
    h('div', { style: { flex: '1', minWidth: '280px', fontSize: '14px' } },
      h('b', 'How this works: '),
      'every cell runs in your own database session (like a psql window), so later queries can use what earlier ones created. ',
      'Unchanged cells run exactly as written; ', h('b', 'edit anything'), ' and it runs in ', h('b', 'safe mode'), ' (rolled back) unless you switch safe mode off. ',
      h('kbd', 'Ctrl'), '+', h('kbd', 'Enter'), ' runs a cell, ', h('kbd', 'Ctrl'), '+', h('kbd', 'Space'), ' autocompletes.'),
    runAllBtn,
    h('button.btn.btn-small', { onclick: () => { for (const v of views) v.el.querySelector('.results').replaceChildren(); } }, 'Clear results')));

  let section = undefined;
  for (const cell of ch.cells) {
    if (cell.section !== section && cell.section) wrap.append(h('div.section-title', cell.section));
    section = cell.section;
    const v = cellView(ch, cell, controller);
    views.push(v);
    wrap.append(v.el);
  }
  wrap._afterMount = () => {
    for (const v of views) v.cm.refresh();
    if (anchor) {
      const el = document.getElementById(`cell-${anchor}`);
      if (el) { el.scrollIntoView({ block: 'start' }); el.classList.add('flash'); }
    }
  };
  return wrap;
}

// ------------------------------------------------------------------ practice
function exerciseView(ch, ex) {
  const results = h('div.results');
  const verdictBox = h('div.verdict.hidden');
  const st = progress.exerciseState(ex.id);
  const badge = h('span.badge.done' + (st === 'correct' ? '' : '.hidden'), '✓ solved');
  const editorDiv = h('div.editor');
  const solutionBox = h('div.solution.hidden');
  let cm;
  let solutionCm;
  let saveTimer;

  const run = async () => {
    const resp = await execute('/api/exercise/run', { chapter: ch.id, exerciseId: ex.id, sql: cm.getValue() }, `Running ${ex.id}…`);
    if (resp) renderRun(results, resp, cm);
  };

  const check = async () => {
    if (!cm.getValue().trim()) { toast('Write a query first'); return; }
    const resp = await execute('/api/exercise/check', { chapter: ch.id, exerciseId: ex.id, sql: cm.getValue() }, `Checking ${ex.id}…`);
    if (!resp) return;
    verdictBox.className = `verdict ${resp.verdict}`;
    const icon = { correct: '✅', order: '🔀', manual: '📝', wrong: '❌', error: '⚠️' }[resp.verdict] || '';
    verdictBox.replaceChildren(`${icon} ${resp.message}`);
    if (resp.missing?.length || resp.extra?.length) {
      verdictBox.append(h('div.diff',
        resp.missing?.length ? `Missing (expected but not returned):\n${resp.missing.map((r) => '  ' + JSON.stringify(r)).join('\n')}\n` : '',
        resp.extra?.length ? `Unexpected (returned but not expected):\n${resp.extra.map((r) => '  ' + JSON.stringify(r)).join('\n')}` : ''));
    }
    if (resp.verdict === 'manual') {
      verdictBox.append(h('div', { style: { marginTop: '8px' } },
        h('button.btn.btn-small.btn-ok', { onclick: () => { progress.markExercise(ex.id, 'correct'); badge.classList.remove('hidden'); toast('Marked as done', 'ok'); } }, '✓ Mark as done'),
        ' ', h('button.btn.btn-small', { onclick: toggleSolution }, 'Compare with the solution')));
    }
    if (resp.expected && resp.verdict !== 'correct') {
      verdictBox.append(h('details.expected', h('summary', `Expected result (${resp.expected.totalRows} rows)`), renderTable(resp.expected)));
    }
    if (resp.attempt) renderRun(results, resp.attempt, cm);
    if (resp.verdict === 'correct') {
      progress.markExercise(ex.id, 'correct');
      badge.classList.remove('hidden');
      toast(`${ex.id} solved! 🎉`, 'ok');
    }
  };

  const toggleSolution = () => {
    solutionBox.classList.toggle('hidden');
    if (!solutionCm && !solutionBox.classList.contains('hidden')) {
      const ed = h('div.editor');
      const solResults = h('div.results');
      solutionBox.append(
        h('h4', 'Solution'),
        ex.solutionKeywords?.length ? h('div.kw', { style: { marginBottom: '8px' } }, ex.solutionKeywords.map((k) => h('span', k))) : null,
        ed,
        h('div.cell-actions',
          h('button.btn.btn-small', { onclick: () => { cm.setValue(ex.solution); toast('Solution copied into your editor'); } }, '⧉ Copy into my editor'),
          h('button.btn.btn-small', {
            onclick: async () => {
              const resp = await execute('/api/exercise/run', { chapter: ch.id, exerciseId: ex.id, sql: ex.solution, safe: true }, `Running solution ${ex.id}…`);
              if (resp) renderRun(solResults, resp, solutionCm);
            },
          }, '▶ Run solution (rolled back)')),
        solResults);
      solutionCm = makeEditor(ed, ex.solution, { readOnly: true });
      setTimeout(() => solutionCm.refresh(), 0);
    }
  };

  const q = ex.question.split('\n');
  const el = h('div.cell.exercise', { id: `cell-${ex.id}` },
    h('div.cell-head', h('span.cell-id', ex.id), ex.difficulty ? h(`span.badge.${ex.difficulty}`, ex.difficulty) : null, badge),
    h('div.cell-meta',
      h('div.question-text', q[0]),
      ...q.slice(1).map((line) => h('div.notes', '💡 ', line))),
    editorDiv,
    h('div.cell-actions',
      h('button.btn.btn-small', { onclick: run, title: 'Ctrl/Cmd + Enter' }, '▶ Run'),
      h('button.btn.btn-primary.btn-small', { onclick: check }, '✔ Check answer'),
      h('button.btn.btn-small', { onclick: toggleSolution }, '💡 Solution'),
      h('button.btn.btn-small.btn-ghost', { onclick: () => { cm.setValue(''); results.replaceChildren(); verdictBox.classList.add('hidden'); } }, 'Clear'),
      h('span.mode-tag', state.safe ? 'safe mode: changes are rolled back' : 'safe mode OFF: changes are kept')),
    verdictBox,
    results,
    solutionBox);

  cm = makeEditor(editorDiv, progress.attempt(ex.id), {
    onRun: run,
    placeholder: `-- ${ex.id}: write your SQL here.\n-- Ctrl+Enter = run · "Check answer" compares your result with the expected one.`,
    onChange: (v) => { clearTimeout(saveTimer); saveTimer = setTimeout(() => progress.saveAttempt(ex.id, v), 400); },
  });
  return { el, cm };
}

function practiceTab(ch, anchor) {
  const wrap = h('div');
  const solved = ch.exercises.filter((e) => progress.exerciseState(e.id) === 'correct').length;
  wrap.append(h('div.card.practice-intro', { style: { fontSize: '14px' } },
    h('b', `${solved} / ${ch.exercises.length} solved. `),
    'Write a query, ', h('b', '▶ Run'), ' it to explore, then ', h('b', '✔ Check answer'),
    ' — your result is compared with the official solution (same columns, same rows; order matters only when the task asks for it). ',
    'Each exercise first recreates the objects earlier exercises would have built, so you can do them in any order. Your attempts are saved in this browser.'));
  const views = ch.exercises.map((ex) => exerciseView(ch, ex));
  views.forEach((v) => wrap.append(v.el));
  wrap._afterMount = () => {
    views.forEach((v) => v.cm.refresh());
    if (anchor) document.getElementById(`cell-${anchor}`)?.scrollIntoView({ block: 'start' });
  };
  return wrap;
}

// ------------------------------------------------------------------ entry
export async function chapterView(main, id, tab, anchor) {
  const ch = await getChapter(id);
  const meta = state.chapters.find((c) => c.id === id);
  tab = tab || 'lesson';
  if (tab === 'lesson' && anchor) anchor = anchor.replace(/^#/, '');
  const body = tab === 'queries' ? queriesTab(ch, anchor) : tab === 'practice' ? practiceTab(ch, anchor) : lessonTab(ch);
  const page = h('div.page', chapterHeader(ch, meta, tab), body);
  main.replaceChildren(page);
  body._afterMount?.();
  if (tab === 'lesson') {
    await renderMermaid(page);
    if (anchor) page.querySelector(`#${CSS.escape(anchor)}`)?.scrollIntoView({ block: 'start' });
  }
  progress.setLast(location.hash);
  // keep the header progress bar fresh
  const refresh = () => { if (document.body.contains(page)) page.firstChild.replaceWith(chapterHeader(ch, meta, tab)); else document.removeEventListener('progress', refresh); };
  document.addEventListener('progress', refresh);
}

export { api, $ };
