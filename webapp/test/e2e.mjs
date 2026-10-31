// End-to-end check against a running server:
//   1. runs every cell (setup + query) of every chapter, in order, exactly as written
//   2. checks every exercise using its own solution as the attempt (must grade as correct/manual)
// Usage: node test/e2e.mjs [http://localhost:3000] [chapter ids…]
const base = process.argv[2]?.startsWith('http') ? process.argv[2] : 'http://localhost:3000';
const only = process.argv.slice(2).filter((a) => /^\d{2}$/.test(a));
const sessionId = 'e2e-' + Math.random().toString(36).slice(2, 12);

const post = async (url, body) => {
  const r = await fetch(base + url, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json();
  if (!r.ok) throw new Error(j.error || r.statusText);
  return j;
};

const chapters = (await (await fetch(base + '/api/chapters')).json()).filter((c) => !only.length || only.includes(c.id));
let failures = 0;
let cellsRun = 0;
let checks = { correct: 0, manual: 0, order: 0 };

for (const meta of chapters) {
  const ch = await (await fetch(`${base}/api/chapters/${meta.id}`)).json();
  if (!ch.cells.length) continue;
  await post('/api/session/reset', { sessionId });
  const t0 = Date.now();
  for (const cell of ch.cells) {
    const out = await post('/api/run', { sessionId, sql: cell.sql, safe: true, ref: { chapter: ch.id, cellId: cell.id } });
    cellsRun++;
    if (!out.trusted) { failures++; console.log(`  ✗ ${cell.id}: not recognised as an unchanged playbook cell`); }
    const err = out.results.find((r) => r.error);
    if (err) { failures++; console.log(`  ✗ ${ch.id} ${cell.id} ${cell.title}: ${err.error.message}`); }
  }
  for (const ex of ch.exercises) {
    const out = await post('/api/exercise/check', { sessionId, chapter: ch.id, exerciseId: ex.id, sql: ex.solution });
    checks[out.verdict] = (checks[out.verdict] || 0) + 1;
    if (!['correct', 'manual'].includes(out.verdict)) { failures++; console.log(`  ✗ ${ex.id}: ${out.verdict} — ${out.message}`); }
  }
  console.log(`${ch.dir.padEnd(28)} ${String(ch.cells.length).padStart(3)} cells, ${String(ch.exercises.length).padStart(2)} exercises  (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
}
await post('/api/session/reset', { sessionId });
console.log(`\n${cellsRun} cells executed, exercise verdicts: ${JSON.stringify(checks)}, failures: ${failures}`);
process.exit(failures ? 1 : 0);
