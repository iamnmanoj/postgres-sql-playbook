// Reads the playbook folder and turns each chapter into structured data:
// README markdown, notebook "cells" from queries.sql, exercises + solutions.
import fs from 'node:fs';
import path from 'node:path';
import { isBlank } from './sqlsplit.js';

const CATEGORIES = {
  '00': 'Setup', '01': 'Foundations', '02': 'Foundations',
  '03': 'Querying basics', '04': 'Querying basics',
  '05': 'Analysis', '06': 'Analysis', '07': 'Analysis',
  '08': 'Advanced querying', '09': 'Advanced querying',
  '10': 'Changing data', '11': 'Changing data',
  '12': 'Rich data types', '13': 'Rich data types',
  '14': 'Performance',
  '15': 'Database programming', '16': 'Database programming', '17': 'Database programming',
  '18': 'Scale & operations', '19': 'Scale & operations', '20': 'Scale & operations',
};

const DASHES = /^-- -{10,}\s*$/;
const EQUALS = /^-- ={10,}\s*$/;
const QUERY_HEADER = /^-- \[(Q\d{2}\.\d{2})\]\s+(.*)$/;
const EX_HEADER = /^-- \[(E\d{2}\.\d{2})\]\s*(?:\((easy|medium|hard)\))?\s*(.*)$/;

const read = (p) => (fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : '');

/** Drop leading comment-only / blank lines (used for setup cells & preambles). */
function trimLeadingComments(sql) {
  const lines = sql.split('\n');
  while (lines.length && (lines[0].trim() === '' || lines[0].trim().startsWith('--'))) lines.shift();
  return lines.join('\n').trim();
}

function trimBlankLines(sql) {
  return sql.replace(/^\s*\n/, '').replace(/\s+$/, '');
}

/** Parse queries.sql into an ordered list of cells (setup + query). */
export function parseQueries(text) {
  const lines = text.split('\n');
  const cells = [];
  let section = null;
  let current = { type: 'setup', section, lines: [] };
  let setupCount = 0;

  const flush = () => {
    const raw = current.lines.join('\n');
    if (current.type === 'query') {
      current.sql = trimBlankLines(raw);
      delete current.lines;
      cells.push(current);
    } else if (!isBlank(raw)) {
      setupCount++;
      cells.push({
        type: 'setup',
        id: `setup-${setupCount}`,
        title: section ? `Setup · ${section}` : 'Chapter setup',
        section,
        sql: trimLeadingComments(raw),
      });
    }
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    // section banner:  -- ====  /  -- SECTION: name  /  -- ====
    if (EQUALS.test(line) && /^-- SECTION:\s*(.+)$/.test(lines[i + 1] || '')) {
      flush();
      section = /^-- SECTION:\s*(.+)$/.exec(lines[i + 1])[1].trim();
      i += EQUALS.test(lines[i + 2] || '') ? 2 : 1;
      current = { type: 'setup', section, lines: [] };
      continue;
    }
    // query header:  -- ----  /  -- [Qnn.mm] title  /  -- Keywords: …  /  …  /  -- ----
    if (DASHES.test(line) && QUERY_HEADER.test(lines[i + 1] || '')) {
      flush();
      const [, id, title] = QUERY_HEADER.exec(lines[i + 1]);
      const cell = { type: 'query', id, title: title.trim(), section, keywords: [], question: '', notes: [], lines: [] };
      let j = i + 2;
      while (j < lines.length && lines[j].startsWith('--') && !DASHES.test(lines[j])) {
        const body = lines[j].replace(/^--\s?/, '');
        let m;
        if ((m = /^Keywords:\s*(.*)$/.exec(body))) cell.keywords = m[1].split(',').map((k) => k.trim()).filter(Boolean);
        else if ((m = /^Business question:\s*(.*)$/.exec(body))) cell.question = m[1].trim();
        else if (/^\s{2,}\S/.test(body) && cell.notes.length) cell.notes[cell.notes.length - 1] += ' ' + body.trim();
        else if (/^\s{2,}\S/.test(body) && cell.question && !cell.notes.length) cell.question += ' ' + body.trim();
        else if (body.trim()) cell.notes.push(body.trim());
        j++;
      }
      if (DASHES.test(lines[j] || '')) j++;
      i = j - 1;
      current = cell;
      continue;
    }
    current.lines.push(line);
  }
  flush();
  return cells;
}

/** Parse exercises.sql: header + continuation comment lines until a blank line. */
export function parseExercises(text) {
  const lines = text.split('\n');
  const out = [];
  let cur = null;
  for (const line of lines) {
    const m = EX_HEADER.exec(line);
    if (m) {
      cur = { id: m[1], difficulty: m[2] || null, question: m[3].trim() };
      out.push(cur);
    } else if (cur && line.startsWith('--') && !EQUALS.test(line)) {
      const body = line.replace(/^--\s?/, '').trim();
      if (body) cur.question += (/^Hint:/i.test(body) ? '\n' : ' ') + body;
    } else {
      cur = null;
    }
  }
  return out;
}

/** Parse solutions.sql into { preamble, blocks: Map(id -> {sql, keywords}) }. */
export function parseSolutions(text) {
  const lines = text.split('\n');
  const blocks = new Map();
  const pre = [];
  let cur = null;
  for (const line of lines) {
    const m = /^-- \[(E\d{2}\.\d{2})\]/.exec(line);
    if (m) {
      cur = { id: m[1], keywords: [], lines: [] };
      blocks.set(m[1], cur);
      continue;
    }
    if (!cur) { pre.push(line); continue; }
    const k = /^-- Keywords:\s*(.*)$/.exec(line);
    if (k && cur.lines.every((l) => l.trim() === '')) { cur.keywords = k[1].split(',').map((x) => x.trim()).filter(Boolean); continue; }
    cur.lines.push(line);
  }
  for (const b of blocks.values()) { b.sql = trimBlankLines(b.lines.join('\n')); delete b.lines; }
  return { preamble: trimLeadingComments(pre.join('\n')), blocks };
}

export class Playbook {
  constructor(root) {
    this.root = root;
    this.chaptersDir = path.join(root, 'chapters');
    this.cache = new Map();
  }

  chapterDirs() {
    return fs.readdirSync(this.chaptersDir, { withFileTypes: true })
      .filter((d) => d.isDirectory() && /^\d{2}_/.test(d.name))
      .map((d) => d.name)
      .sort();
  }

  dirFor(id) {
    return this.chapterDirs().find((d) => d.startsWith(id + '_'));
  }

  /** Summary list for the sidebar. */
  list() {
    return this.chapterDirs().map((dir) => {
      const ch = this.get(dir.slice(0, 2));
      return {
        id: ch.id, dir, title: ch.title, shortTitle: ch.shortTitle, category: ch.category,
        queryCount: ch.cells.filter((c) => c.type === 'query').length,
        exerciseCount: ch.exercises.length,
      };
    });
  }

  /** Full chapter (cached by file mtimes so edits show up without restart). */
  get(id) {
    const dir = this.dirFor(id);
    if (!dir) return null;
    const base = path.join(this.chaptersDir, dir);
    const files = ['README.md', 'queries.sql', 'exercises.sql', 'solutions.sql'].map((f) => path.join(base, f));
    const stamp = files.map((f) => (fs.existsSync(f) ? fs.statSync(f).mtimeMs : 0)).join('|');
    const hit = this.cache.get(id);
    if (hit && hit.stamp === stamp) return hit.data;

    const readme = read(files[0]);
    const title = (readme.split('\n')[0] || dir).replace(/^#\s*/, '').trim();
    const cells = parseQueries(read(files[1]));
    const solutions = parseSolutions(read(files[3]));
    const exercises = parseExercises(read(files[2])).map((e) => ({
      ...e,
      solution: solutions.blocks.get(e.id)?.sql || '',
      solutionKeywords: solutions.blocks.get(e.id)?.keywords || [],
    }));
    const data = {
      id, dir, title,
      shortTitle: title.replace(/^Chapter \d+\s*·\s*/, ''),
      category: CATEGORIES[id] || 'Other',
      readme, cells, exercises,
      solutionsPreamble: solutions.preamble,
    };
    this.cache.set(id, { stamp, data });
    return data;
  }

  cell(chapterId, cellId) {
    return this.get(chapterId)?.cells.find((c) => c.id === cellId) || null;
  }

  /** SQL that recreates the state an exercise's solution expects: preamble + earlier solutions. */
  exerciseContext(chapterId, exerciseId) {
    const ch = this.get(chapterId);
    if (!ch) return null;
    const idx = ch.exercises.findIndex((e) => e.id === exerciseId);
    if (idx === -1) return null;
    const parts = [ch.solutionsPreamble, ...ch.exercises.slice(0, idx).map((e) => e.solution)];
    return { exercise: ch.exercises[idx], contextSql: parts.filter(Boolean).join('\n') };
  }

  /** Lightweight search index of every query cell. */
  index() {
    return this.chapterDirs().flatMap((dir) => {
      const ch = this.get(dir.slice(0, 2));
      return ch.cells.filter((c) => c.type === 'query').map((c) => ({
        chapter: ch.id, chapterTitle: ch.shortTitle, id: c.id, title: c.title,
        keywords: c.keywords, question: c.question, section: c.section,
      }));
    });
  }

  /** Top-level markdown docs (README, GLOSSARY, TIPS, KEYWORD_INDEX). */
  doc(name) {
    const allowed = ['README', 'GLOSSARY', 'TIPS', 'KEYWORD_INDEX'];
    if (!allowed.includes(name)) return null;
    return read(path.join(this.root, `${name}.md`));
  }

  /** Read any text file inside the playbook (for schema.sql / seed viewer). */
  file(rel) {
    const full = path.resolve(this.root, rel);
    if (!full.startsWith(path.resolve(this.root) + path.sep)) return null;
    if (!/\.(sql|md|csv|yml|sh)$/.test(full) || !fs.existsSync(full)) return null;
    if (full.includes(`${path.sep}node_modules${path.sep}`)) return null;
    return fs.readFileSync(full, 'utf8');
  }
}
