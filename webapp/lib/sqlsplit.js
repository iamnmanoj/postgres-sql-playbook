// Split a SQL script into statements the way psql does, so each statement can be
// executed (and reported) separately. Handles:
//   'strings' (incl. '' escapes and E'\'' escapes), "identifiers", $tag$ dollar quotes $tag$,
//   -- line comments, /* nested block comments */, BEGIN ATOMIC … END bodies,
//   and psql backslash meta-commands (\gset, \gexec, \crosstabview, \copy, \set, …).
//
// Returns an array of items:
//   { kind: 'sql',  text, start, end, meta: null | { cmd, args } }   (meta = terminating \g-style command)
//   { kind: 'meta', cmd, args, start, end }                          (stand-alone meta-command)

const IDENT_START = /[A-Za-z_\u0080-\uffff]/;
const IDENT_CHAR = /[A-Za-z0-9_$\u0080-\uffff]/;
const TERMINATING_META = new Set(['g', 'gx', 'gset', 'gexec', 'crosstabview']);

function readDollarTag(text, i) {
  // text[i] === '$'; returns the full tag ("$tag$" or "$$") or null
  const m = /^\$([A-Za-z_\u0080-\uffff][A-Za-z0-9_\u0080-\uffff]*)?\$/.exec(text.slice(i, i + 64));
  return m ? m[0] : null;
}

/** Remove comments and whitespace; true when nothing executable is left. */
export function isBlank(sql) {
  return stripComments(sql).trim() === '';
}

/** Return sql with comments removed (strings/dollar quotes preserved). */
export function stripComments(sql) {
  let out = '';
  scan(sql, (type, chunk) => { if (type !== 'comment') out += chunk; });
  return out;
}

/**
 * Generic lexer: calls emit(type, chunk) for consecutive chunks where type is
 * 'code' | 'string' | 'ident' | 'dollar' | 'comment'.
 */
export function scan(text, emit) {
  let i = 0;
  const n = text.length;
  let code = '';
  const flush = () => { if (code) { emit('code', code); code = ''; } };
  while (i < n) {
    const c = text[i];
    const next = text[i + 1];
    if (c === '-' && next === '-') {
      flush();
      const j = text.indexOf('\n', i);
      const end = j === -1 ? n : j;
      emit('comment', text.slice(i, end));
      i = end;
    } else if (c === '/' && next === '*') {
      flush();
      let depth = 1;
      let j = i + 2;
      while (j < n && depth > 0) {
        if (text[j] === '/' && text[j + 1] === '*') { depth++; j += 2; }
        else if (text[j] === '*' && text[j + 1] === '/') { depth--; j += 2; }
        else j++;
      }
      emit('comment', text.slice(i, j));
      i = j;
    } else if (c === "'") {
      flush();
      const prev = text[i - 1];
      const escaped = (prev === 'E' || prev === 'e') && !IDENT_CHAR.test(text[i - 2] || ' ');
      let j = i + 1;
      while (j < n) {
        if (escaped && text[j] === '\\') { j += 2; continue; }
        if (text[j] === "'") {
          if (text[j + 1] === "'") { j += 2; continue; }
          j++;
          break;
        }
        j++;
      }
      emit('string', text.slice(i, j));
      i = j;
    } else if (c === '"') {
      flush();
      let j = i + 1;
      while (j < n) {
        if (text[j] === '"') {
          if (text[j + 1] === '"') { j += 2; continue; }
          j++;
          break;
        }
        j++;
      }
      emit('ident', text.slice(i, j));
      i = j;
    } else if (c === '$' && !IDENT_CHAR.test(text[i - 1] || ' ') && readDollarTag(text, i)) {
      flush();
      const tag = readDollarTag(text, i);
      const close = text.indexOf(tag, i + tag.length);
      const end = close === -1 ? n : close + tag.length;
      emit('dollar', text.slice(i, end));
      i = end;
    } else {
      code += c;
      i++;
    }
  }
  flush();
}

/** Split a script into executable items. */
export function splitSql(text) {
  const items = [];
  const n = text.length;
  let i = 0;
  let stmtStart = 0;
  let words = [];          // first top-level words of the current statement (upper case)
  let atomicDepth = 0;     // BEGIN ATOMIC / CASE … END nesting inside CREATE FUNCTION/PROCEDURE

  const isRoutineDef = () => {
    const w = words.filter((x) => x !== 'OR' && x !== 'REPLACE');
    return w[0] === 'CREATE' && (w[1] === 'FUNCTION' || w[1] === 'PROCEDURE');
  };
  const pushStatement = (end, meta) => {
    const raw = text.slice(stmtStart, end);
    if (!isBlank(raw)) items.push({ kind: 'sql', text: raw.trim(), start: stmtStart + (raw.length - raw.trimStart().length), end, meta });
    else if (meta) items.push({ kind: 'meta', cmd: meta.cmd, args: meta.args, start: stmtStart, end });
    words = [];
    atomicDepth = 0;
  };

  while (i < n) {
    const c = text[i];
    const next = text[i + 1];
    if (c === '-' && next === '-') {
      const j = text.indexOf('\n', i);
      i = j === -1 ? n : j;
    } else if (c === '/' && next === '*') {
      let depth = 1;
      let j = i + 2;
      while (j < n && depth > 0) {
        if (text[j] === '/' && text[j + 1] === '*') { depth++; j += 2; }
        else if (text[j] === '*' && text[j + 1] === '/') { depth--; j += 2; }
        else j++;
      }
      i = j;
    } else if (c === "'") {
      const prev = text[i - 1];
      const escaped = (prev === 'E' || prev === 'e') && !IDENT_CHAR.test(text[i - 2] || ' ');
      let j = i + 1;
      while (j < n) {
        if (escaped && text[j] === '\\') { j += 2; continue; }
        if (text[j] === "'") { if (text[j + 1] === "'") { j += 2; continue; } j++; break; }
        j++;
      }
      i = j;
    } else if (c === '"') {
      let j = i + 1;
      while (j < n) { if (text[j] === '"') { if (text[j + 1] === '"') { j += 2; continue; } j++; break; } j++; }
      i = j;
    } else if (c === '$' && !IDENT_CHAR.test(text[i - 1] || ' ') && readDollarTag(text, i)) {
      const tag = readDollarTag(text, i);
      const close = text.indexOf(tag, i + tag.length);
      i = close === -1 ? n : close + tag.length;
    } else if (c === '\\') {
      // psql meta-command: runs to end of line
      const j = text.indexOf('\n', i);
      const end = j === -1 ? n : j;
      const line = text.slice(i + 1, end).trim();
      const m = /^([A-Za-z_]+|[!?])\s*(.*)$/.exec(line) || ['', line, ''];
      const cmd = m[1];
      const args = m[2] || '';
      if (TERMINATING_META.has(cmd)) {
        pushStatement(i, { cmd, args });
      } else {
        // stand-alone meta: flush any finished statement text first only if it ended with ';' (it did, else keep)
        if (!isBlank(text.slice(stmtStart, i))) pushStatement(i, null);   // run buffered text first
        items.push({ kind: 'meta', cmd, args, start: i, end });
      }
      i = end;
      stmtStart = end;
      if (!TERMINATING_META.has(cmd)) words = [];
    } else if (c === ';' && atomicDepth === 0) {
      pushStatement(i, null);
      i++;
      stmtStart = i;
    } else if (IDENT_START.test(c) && !IDENT_CHAR.test(text[i - 1] || ' ')) {
      let j = i + 1;
      while (j < n && IDENT_CHAR.test(text[j])) j++;
      const w = text.slice(i, j).toUpperCase();
      if (words.length < 4) words.push(w);
      if (isRoutineDef()) {
        if (w === 'BEGIN' || w === 'CASE') atomicDepth++;
        else if (w === 'END' && atomicDepth > 0) atomicDepth--;
      }
      i = j;
    } else {
      i++;
    }
  }
  pushStatement(n, null);
  return items;
}

/** psql-style variable interpolation: :name, :'name' (literal), :"name" (identifier). */
export function substituteVars(sql, vars) {
  if (!vars || Object.keys(vars).length === 0) return sql;
  const has = (name) => Object.prototype.hasOwnProperty.call(vars, name);
  let out = '';
  scan(sql, (type, chunk) => {
    if (type === 'code') {
      out += chunk.replace(/(::)|:([A-Za-z0-9_]+)/g, (all, cast, name) => (cast ? cast : has(name) ? String(vars[name]) : all));
      return;
    }
    // :'name' / :"name" are lexed as ':' (code) followed by a string / quoted identifier
    const m = /^(['"])([A-Za-z0-9_]+)\1$/.exec(chunk);
    if ((type === 'string' || type === 'ident') && m && out.endsWith(':') && !out.endsWith('::') && has(m[2])) {
      out = out.slice(0, -1) + (type === 'string' ? quoteLiteral(vars[m[2]]) : '"' + String(vars[m[2]]).replace(/"/g, '""') + '"');
      return;
    }
    out += chunk;
  });
  return out;
}

export function quoteLiteral(v) {
  return "'" + String(v).replace(/'/g, "''") + "'";
}

/** First keyword(s) of a statement, upper case, comments skipped. */
export function leadingKeywords(sql, count = 2) {
  const words = stripComments(sql).trim().split(/\s+/).slice(0, count);
  return words.map((w) => w.replace(/;$/, '').toUpperCase());
}

/** Classify transaction-control statements. Returns null for normal statements. */
export function transactionControl(sql) {
  const [a, b] = leadingKeywords(sql, 2);
  if (a === 'BEGIN' || a === 'START') return 'begin';
  if (a === 'COMMIT' || a === 'END') return b === 'PREPARED' ? 'commit-prepared' : 'commit';
  if (a === 'ABORT') return 'rollback';
  if (a === 'ROLLBACK') return b === 'TO' ? null : 'rollback';
  return null;
}
