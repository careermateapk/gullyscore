// Runs the Worker against a real SQLite database (node:sqlite) to check the API.
// Usage: node --experimental-sqlite test/run.mjs
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import worker from '../src/index.js';

const db = new DatabaseSync(':memory:');
db.exec(readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8'));

// Minimal D1 look-alike.
function stmt(sql) {
  let args = [];
  const s = {
    bind: (...a) => ((args = a), s),
    first: async () => db.prepare(sql).get(...args) ?? null,
    all: async () => ({ results: db.prepare(sql).all(...args) }),
    run: async () => {
      const r = db.prepare(sql).run(...args);
      return { meta: { changes: Number(r.changes) } };
    },
  };
  return s;
}
const env = {
  DB: {
    prepare: stmt,
    batch: async (list) => {
      db.exec('BEGIN');
      try {
        for (const s of list) await s.run();
        db.exec('COMMIT');
      } catch (e) {
        db.exec('ROLLBACK');
        throw e;
      }
    },
  },
};
const call = async (method, path, body, token) => {
  const r = await worker.fetch(
    new Request('https://x.test' + path, {
      method,
      headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    env,
  );
  const text = await r.text();
  let j = null;
  try { j = JSON.parse(text); } catch { j = text; }
  return { status: r.status, body: j };
};

const reg = await call('POST', '/v1/register');
assert.equal(reg.status, 200);
const tok = reg.body.scorerId + '.' + reg.body.token;
const other = await call('POST', '/v1/register');
const tok2 = other.body.scorerId + '.' + other.body.token;

const summary = { title: 'A vs B', status: 'B need 10', finished: false, innings: [{ team: 'A', score: '20/1', overs: '2.0', extras: '1', batting: [{ name: 'Ravi', out: 'not out', r: 12, b: 8, '4s': 1, '6s': 1, onStrike: true }], bowling: [{ name: 'Sanjay', o: '2.0', m: 0, r: 20, w: 1 }], fow: [] }], thisOver: ['1', '4'] };
const put = await call('PUT', '/v1/matches/m_123', { data: { match: { id: 'm_123' } }, summary, players: ['p1', 'p2', 'bad id!'], finished: false, title: 'MPL' }, tok);
assert.equal(put.status, 200);
assert.equal((await call('PUT', '/v1/matches/m_123', { data: {}, summary }, tok2)).status, 403, 'others cannot overwrite');
assert.equal((await call('PUT', '/v1/matches/m_123', { data: {}, summary })).status, 401, 'must sign in');
assert.equal((await call('PUT', '/v1/matches/m_123', { data: {}, summary }, reg.body.scorerId + '.wrong')).status, 401, 'wrong token');

const got = await call('GET', '/v1/matches/m_123');
assert.equal(got.status, 200);
assert.equal(got.body.summary.status, 'B need 10');
const same = await call('GET', '/v1/matches/m_123?since=' + got.body.updated);
assert.equal(same.body.unchanged, true);
assert.equal((await call('GET', '/v1/matches/nope')).status, 404);

const pm = await call('GET', '/v1/players/p1/matches');
assert.equal(pm.body.matches.length, 1);
assert.equal((await call('GET', '/v1/players/bad id!/matches')).body.matches?.length ?? 0, 0);

const inv = await call('POST', '/v1/invites', { playerId: 'p1', name: 'Ravi', team: 'A' }, tok);
assert.equal(inv.status, 200);
assert.match(inv.body.code, /^[A-Z2-9]{8}$/);
const inv2 = await call('POST', '/v1/invites', { playerId: 'p1', name: 'Ravi' }, tok);
assert.equal(inv2.body.code, inv.body.code, 'same code for same player');
const look = await call('GET', '/v1/invites/' + inv.body.code.toLowerCase());
assert.equal(look.body.playerId, 'p1');
assert.equal((await call('GET', '/v1/invites/ZZZZZZZZ')).status, 404);

const page = await call('GET', '/m/m_123');
assert.ok(String(page.body).includes('Live score'));
const ipage = await call('GET', '/p/' + inv.body.code);
assert.ok(String(ipage.body).includes('Ravi'));
const xss = await call('POST', '/v1/invites', { playerId: 'p9', name: '<script>alert(1)</script>' }, tok);
const xpage = await call('GET', '/p/' + xss.body.code);
assert.ok(!String(xpage.body).includes('<script>alert'), 'names are escaped');

assert.equal((await call('DELETE', '/v1/matches/m_123', undefined, tok2)).status, 403);
assert.equal((await call('DELETE', '/v1/matches/m_123', undefined, tok)).status, 200);
assert.equal((await call('GET', '/v1/matches/m_123')).status, 404);
assert.equal((await call('GET', '/v1/players/p1/matches')).body.matches.length, 0);

const big = await call('PUT', '/v1/matches/m_big', { data: { x: 'a'.repeat(700 * 1024) }, summary }, tok);
assert.equal(big.status, 413);
console.log('server tests passed');
