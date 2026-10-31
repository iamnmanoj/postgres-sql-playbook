// Entry point: sidebar, router, search, top bar controls.
import { h, $, api, state, progress, toast, applyTheme, chapterRoute } from './js/util.js';
import { chapterView } from './js/chapter.js';
import { homeView, scratchView, schemaView, docView, fileView, mdFileView } from './js/pages.js';

const main = $('#main');

// ------------------------------------------------------------------ sidebar
function renderSidebar() {
  const nav = $('#chapter-nav');
  const groups = [];
  let cat = null;
  for (const c of state.chapters) {
    if (c.category !== cat) { cat = c.category; groups.push(h('div.nav-cat', cat)); }
    const s = progress.chapterStats(c);
    const pct = s.total ? Math.round((100 * s.done) / s.total) : 0;
    groups.push(h('a', { href: chapterRoute(c.id), 'data-nav': `chapter/${c.id}`, title: c.title },
      h('span.nav-num', c.id),
      h('span.nav-title', c.shortTitle.replace(/`/g, '').replace(/:.*$/, '')),
      s.total ? h('span.nav-progress', h('span', { style: { width: pct + '%' } })) : null));
  }
  nav.replaceChildren(...groups);
  highlightNav();
}

function highlightNav() {
  const hash = location.hash.replace(/^#\/?/, '');
  for (const a of document.querySelectorAll('[data-nav]')) {
    const key = a.dataset.nav;
    const active = key === 'home' ? hash === '' : hash === key || hash.startsWith(key + '/');
    a.classList.toggle('active', active);
  }
}

// ------------------------------------------------------------------ router
let currentKey = null;
async function route() {
  const hash = decodeURIComponent(location.hash.replace(/^#\/?/, ''));
  const parts = hash.split('/');
  highlightNav();
  document.body.classList.remove('sidebar-open');

  // same chapter tab → just scroll to the anchor
  if (parts[0] === 'chapter') {
    const key = `chapter/${parts[1]}/${parts[2] || 'lesson'}`;
    if (key === currentKey && parts[3]) {
      const el = document.getElementById(`cell-${parts[3]}`);
      if (el) { el.scrollIntoView({ behavior: 'smooth', block: 'start' }); el.classList.remove('flash'); void el.offsetWidth; el.classList.add('flash'); return; }
    }
    currentKey = key;
  } else {
    currentKey = hash;
  }

  state.editors.clear();
  main.scrollTop = 0;
  main.replaceChildren(h('div.page', h('p.muted', 'Loading…')));
  try {
    if (!hash) await homeView(main);
    else if (parts[0] === 'chapter') await chapterView(main, parts[1], parts[2], parts.slice(3).join('/') || null);
    else if (parts[0] === 'scratch') scratchView(main);
    else if (parts[0] === 'schema') await schemaView(main);
    else if (parts[0] === 'doc') await docView(main, parts[1], (parts[2] || '').replace(/^#/, '') || null);
    else if (parts[0] === 'file') await fileView(main, parts.slice(1).join('/'));
    else if (parts[0] === 'md') await mdFileView(main, parts.slice(1).join('/'));
    else await homeView(main);
  } catch (e) {
    main.replaceChildren(h('div.page', h('div.db-down', h('b', 'Something went wrong: '), e.message)));
  }
}

// ------------------------------------------------------------------ search
let index = [];
let selected = -1;
function search(q) {
  const box = $('#search-results');
  const terms = q.toLowerCase().split(/\s+/).filter(Boolean);
  if (!terms.length) { box.classList.add('hidden'); return; }
  const hay = (x) => x.toLowerCase();
  const chapterHits = state.chapters
    .filter((c) => terms.every((t) => hay(`${c.id} ${c.title} ${c.category}`).includes(t)))
    .map((c) => ({ href: chapterRoute(c.id), id: `Ch ${c.id}`, title: c.shortTitle.replace(/`/g, ''), sub: c.category }));
  const cellHits = index
    .filter((c) => terms.every((t) => hay(`${c.id} ${c.title} ${c.keywords.join(' ')} ${c.question} ${c.chapterTitle} ${c.section || ''}`).includes(t)))
    .slice(0, 40)
    .map((c) => ({ href: chapterRoute(c.chapter, 'queries', c.id), id: c.id, title: c.title, sub: c.keywords.join(', ') }));
  const hits = [...chapterHits, ...cellHits].slice(0, 50);
  selected = -1;
  box.replaceChildren(...(hits.length ? hits.map((x) =>
    h('a', { href: x.href, onclick: () => closeSearch() }, h('span.sr-id', x.id), x.title, h('span.sr-sub', x.sub)))
    : [h('a', h('span.sr-sub', 'No matches'))]));
  box.classList.remove('hidden');
}
function closeSearch() {
  $('#search-results').classList.add('hidden');
  $('#search').value = '';
}

// ------------------------------------------------------------------ session chip
async function refreshSession() {
  const chip = $('#session-btn');
  try {
    const s = await api(`/api/session/${state.sessionId}`);
    chip.className = 'chip ' + (s.connected ? 'ok' : '');
    $('#session-label').textContent = s.connected ? `session · pid ${s.pid}` : 'session · idle';
    chip.title = s.connected
      ? `Your database session (backend pid ${s.pid}). psql variables: ${Object.keys(s.vars).join(', ') || 'none'}. Click to reset.`
      : 'A database session opens when you run your first query.';
  } catch {
    chip.className = 'chip bad';
    $('#session-label').textContent = 'server offline';
  }
}

// ------------------------------------------------------------------ init
async function init() {
  applyTheme();
  $('#safe-toggle').checked = state.safe;

  $('#theme-btn').addEventListener('click', () => {
    state.theme = state.theme === 'dark' ? 'light' : 'dark';
    localStorage.setItem('pb.theme', state.theme);
    applyTheme();
  });
  $('#safe-toggle').addEventListener('change', (e) => {
    state.safe = e.target.checked;
    localStorage.setItem('pb.safe', String(state.safe));
    toast(state.safe ? '🛡️ Safe mode ON: your edits are rolled back after each run' : '⚠️ Safe mode OFF: your edits change the database (scripts/reset.sh restores it)', state.safe ? 'ok' : '');
    for (const cm of state.editors) CodeMirror.signal(cm, 'change', cm);
  });
  $('#session-btn').addEventListener('click', async () => {
    if (!confirm('Reset your database session? This closes the connection (temp tables, SET values, psql variables and open transactions are discarded).')) return;
    await api('/api/session/reset', { sessionId: state.sessionId });
    toast('Session reset', 'ok');
    refreshSession();
  });
  $('#cancel-btn').addEventListener('click', async () => {
    const r = await api('/api/cancel', { sessionId: state.sessionId });
    toast(r.cancelled ? 'Cancel request sent' : 'Nothing to cancel');
  });
  $('#menu-toggle').addEventListener('click', () => {
    if (matchMedia('(max-width: 900px)').matches) document.body.classList.toggle('sidebar-open');
    else document.body.classList.toggle('sidebar-collapsed');
  });
  $('#reset-progress').addEventListener('click', () => {
    if (confirm('Clear all saved progress and exercise attempts in this browser?')) { progress.reset(); toast('Progress cleared'); route(); }
  });

  const input = $('#search');
  input.addEventListener('input', () => search(input.value));
  input.addEventListener('keydown', (e) => {
    const items = [...document.querySelectorAll('#search-results a[href]')];
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      selected = Math.max(0, Math.min(items.length - 1, selected + (e.key === 'ArrowDown' ? 1 : -1)));
      items.forEach((a, i) => a.classList.toggle('sel', i === selected));
      items[selected]?.scrollIntoView({ block: 'nearest' });
    } else if (e.key === 'Enter') {
      const a = items[Math.max(0, selected)];
      if (a) { location.hash = a.getAttribute('href'); closeSearch(); input.blur(); }
    } else if (e.key === 'Escape') { closeSearch(); input.blur(); }
  });
  document.addEventListener('click', (e) => { if (!e.target.closest('.search')) $('#search-results').classList.add('hidden'); });
  document.addEventListener('keydown', (e) => {
    if (e.key === '/' && !e.target.closest('input, textarea, .CodeMirror')) { e.preventDefault(); input.focus(); }
  });

  document.addEventListener('progress', renderSidebar);
  document.addEventListener('session-changed', refreshSession);
  window.addEventListener('hashchange', route);

  try {
    state.chapters = await api('/api/chapters');
  } catch (e) {
    main.replaceChildren(h('div.page', h('div.db-down', 'Cannot reach the server: ', e.message)));
    return;
  }
  renderSidebar();
  // schema (autocomplete + schema browser) loads in the background; pages await state.schemaReady
  state.schemaReady = api('/api/schema').then((tables) => {
    state.schema = tables;
    for (const t of tables) {
      const cols = t.columns.map((c) => c.name);
      state.hintTables[`${t.schema}.${t.table}`] = cols;
      if (!state.hintTables[t.table]) state.hintTables[t.table] = cols;
    }
  }).catch(() => { state.schema = []; });
  await route();
  refreshSession();

  // background: search index
  api('/api/index').then((x) => { index = x; }).catch(() => {});
}

init();
