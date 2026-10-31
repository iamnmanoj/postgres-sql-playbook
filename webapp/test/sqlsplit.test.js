import { test } from 'node:test';
import assert from 'node:assert/strict';
import { splitSql, substituteVars, transactionControl, isBlank } from '../lib/sqlsplit.js';

const texts = (sql) => splitSql(sql).filter((i) => i.kind === 'sql').map((i) => i.text);

test('splits simple statements and ignores comments', () => {
  assert.deepEqual(texts('SELECT 1; -- c;\nSELECT 2;\n/* x; */ SELECT 3'), ['SELECT 1', '-- c;\nSELECT 2', '/* x; */ SELECT 3']);
});

test('semicolons inside strings, identifiers and dollar quotes do not split', () => {
  const sql = `SELECT 'a;b', "x;y", E'it\\'s;';
DO $$ BEGIN RAISE NOTICE 'x;'; END $$;
CREATE FUNCTION f() RETURNS int LANGUAGE sql AS $body$ SELECT 1; $body$;`;
  assert.equal(texts(sql).length, 3);
});

test('dollar sign parameters are not dollar quotes', () => {
  assert.deepEqual(texts('SELECT $1 + $2; SELECT 3'), ['SELECT $1 + $2', 'SELECT 3']);
});

test('BEGIN ATOMIC bodies are kept together', () => {
  const sql = `CREATE OR REPLACE FUNCTION app.f(p text) RETURNS boolean LANGUAGE sql STABLE
BEGIN ATOMIC
    SELECT CASE WHEN p = 'x' THEN true ELSE false END;
END;
SELECT 2;`;
  const t = texts(sql);
  assert.equal(t.length, 2);
  assert.match(t[0], /END$/);
});

test('plain BEGIN … COMMIT is split normally', () => {
  assert.equal(texts('BEGIN; UPDATE t SET a = 1; COMMIT;').length, 3);
});

test('psql meta-commands', () => {
  const items = splitSql("SELECT 1 AS x \\gset\nSELECT :x;\n\\copy t TO 'f.csv' WITH (FORMAT csv)\nSELECT 2 \\crosstabview");
  assert.equal(items[0].kind, 'sql');
  assert.deepEqual(items[0].meta, { cmd: 'gset', args: '' });
  assert.equal(items[1].text, 'SELECT :x');
  assert.equal(items[2].kind, 'meta');
  assert.equal(items[2].cmd, 'copy');
  assert.equal(items[3].meta.cmd, 'crosstabview');
});

test('variable substitution respects casts, strings and quoting', () => {
  const vars = { id: '42', day: "2025-01-01", tbl: 'My Table' };
  assert.equal(substituteVars("SELECT :id::int, ':id', :'day', :\"tbl\", :missing", vars),
    `SELECT 42::int, ':id', '2025-01-01', "My Table", :missing`);
});

test('transaction control detection', () => {
  assert.equal(transactionControl('-- c\nBEGIN ISOLATION LEVEL SERIALIZABLE'), 'begin');
  assert.equal(transactionControl('START TRANSACTION'), 'begin');
  assert.equal(transactionControl('COMMIT'), 'commit');
  assert.equal(transactionControl('ROLLBACK'), 'rollback');
  assert.equal(transactionControl('ROLLBACK TO SAVEPOINT s'), null);
  assert.equal(transactionControl('SELECT 1'), null);
});

test('isBlank', () => {
  assert.ok(isBlank('-- only a comment\n  /* and this */ '));
  assert.ok(!isBlank('-- c\nSELECT 1'));
});
