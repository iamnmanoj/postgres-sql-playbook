// Shared helpers: DOM builder, API client, state, progress storage, CodeMirror factory.

/** Tiny hyperscript: h('div.cls#id', {attrs}, ...children) */
export function h(tag, attrs, ...children) {
  const [, name = 'div', rest = ''] = /^([a-z0-9-]*)(.*)$/i.exec(tag);
  const el = document.createElement(name || 'div');
  for (const part of rest.match(/[.#][^.#]+/g) || []) {
    if (part[0] === '.') el.classList.add(part.slice(1));
    else el.id = part.slice(1);
  }
  if (attrs && (typeof attrs !== 'object' || attrs instanceof Node || Array.isArray(attrs))) {
    children.unshift(attrs);
    attrs = null;
  }
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
    else if (k === 'html') el.innerHTML = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat(Infinity)) {
    if (c === null || c === undefined || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}

export const $ = (sel, root = document) => root.querySelector(sel);

// ---------------- API ----------------
export async function api(path, body) {
  const opts = body === undefined ? {} : { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) };
  const r = await fetch(path, opts);
  const ct = r.headers.get('content-type') || '';
  const data = ct.includes('json') ? await r.json() : await r.text();
  if (!r.ok) throw new Error((data && data.error) || r.statusText);
  return data;
}

// ---------------- state ----------------
const SESSION_KEY = 'pb.session';
export const state = {
  sessionId: sessionStorage.getItem(SESSION_KEY) || (() => {
    const id = 'tab-' + crypto.getRandomValues(new Uint32Array(3)).join('').slice(0, 20);
    sessionStorage.setItem(SESSION_KEY, id);
    return id;
  })(),
  safe: localStorage.getItem('pb.safe') !== 'false',
  theme: localStorage.getItem('pb.theme') || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'),
  chapters: [],
  chapterCache: new Map(),
  hintTables: {},
  editors: new Set(),
  running: 0,
};

export async function getChapter(id) {
  if (!state.chapterCache.has(id)) state.chapterCache.set(id, await api(`/api/chapters/${id}`));
  return state.chapterCache.get(id);
}

// ---------------- progress (localStorage) ----------------
const PKEY = 'pb.progress.v1';
export const progress = {
  data: JSON.parse(localStorage.getItem(PKEY) || '{"queries":{},"exercises":{},"attempts":{},"last":null}'),
  save() { localStorage.setItem(PKEY, JSON.stringify(this.data)); document.dispatchEvent(new Event('progress')); },
  markQuery(id) { if (!this.data.queries[id]) { this.data.queries[id] = Date.now(); this.save(); } },
  markExercise(id, verdict) { this.data.exercises[id] = verdict; this.save(); },
  queryDone(id) { return !!this.data.queries[id]; },
  exerciseState(id) { return this.data.exercises[id] || null; },
  attempt(id) { return this.data.attempts[id] || ''; },
  saveAttempt(id, sql) { this.data.attempts[id] = sql; localStorage.setItem(PKEY, JSON.stringify(this.data)); },
  setLast(route) { this.data.last = route; localStorage.setItem(PKEY, JSON.stringify(this.data)); },
  chapterStats(ch) {
    const q = Object.keys(this.data.queries).filter((k) => k.startsWith(`Q${ch.id}.`)).length;
    const e = Object.entries(this.data.exercises).filter(([k, v]) => k.startsWith(`E${ch.id}.`) && v === 'correct').length;
    return { q, e, total: ch.queryCount + ch.exerciseCount, done: q + e };
  },
  reset() { this.data = { queries: {}, exercises: {}, attempts: {}, last: null }; this.save(); },
};

// ---------------- UI helpers ----------------
let toastTimer;
export function toast(msg, kind = '') {
  const t = $('#toast');
  t.textContent = msg;
  t.className = `toast ${kind}`;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.add('hidden'), 3200);
}

export function setRunning(delta, label) {
  state.running = Math.max(0, state.running + delta);
  $('#running').classList.toggle('hidden', state.running === 0);
  if (label) $('#running-label').textContent = label;
}

export function slug(text) {
  return text.toLowerCase().trim().replace(/[^\p{L}\p{N}\s-]/gu, '').replace(/\s/g, '-');
}

// ---------------- CodeMirror ----------------
export function makeEditor(parent, value, { readOnly = false, onRun, onChange, placeholder, tall = false } = {}) {
  if (tall) parent.classList.add('tall');
  const run = () => { onRun && onRun(); };
  const cm = window.CodeMirror(parent, {
    value,
    mode: 'text/x-pgsql',
    theme: state.theme === 'dark' ? 'material-darker' : 'eclipse',
    lineNumbers: true,
    matchBrackets: true,
    indentUnit: 4,
    tabSize: 4,
    lineWrapping: true,
    viewportMargin: Infinity,
    readOnly,
    placeholder,
    extraKeys: {
      'Ctrl-Enter': run, 'Cmd-Enter': run, 'Shift-Enter': run,
      'Ctrl-Space': 'autocomplete',
      'Ctrl-/': 'toggleComment', 'Cmd-/': 'toggleComment',
      Tab: (c) => (c.somethingSelected() ? c.indentSelection('add') : c.replaceSelection('    ')),
    },
    hintOptions: { tables: state.hintTables, completeSingle: false },
  });
  if (onChange) cm.on('change', () => onChange(cm.getValue()));
  state.editors.add(cm);
  return cm;
}

export function applyTheme() {
  document.documentElement.dataset.theme = state.theme;
  $('#theme-btn').textContent = state.theme === 'dark' ? '☀️' : '🌙';
  for (const cm of state.editors) cm.setOption('theme', state.theme === 'dark' ? 'material-darker' : 'eclipse');
}

export function chapterRoute(id, tab, anchor) {
  return `#/chapter/${id}${tab ? '/' + tab : ''}${anchor ? '/' + anchor : ''}`;
}
