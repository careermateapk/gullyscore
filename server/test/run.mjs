// Runs the Worker against a real SQLite database (node:sqlite) to check the API.
// Usage: node --experimental-sqlite test/run.mjs
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import worker from '../src/index.js';

const db = new DatabaseSync(':memory:');
for (const f of ['0001_init.sql', '0002_login.sql']) db.exec(readFileSync(new URL('../migrations/' + f, import.meta.url), 'utf8'));

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
  // Pretend Google: "good:<sub>:<email>" is a real sign-in, anything else is not.
  VERIFY_GOOGLE: async (t) => {
    const m = /^good:(\w+):(\S+)$/.exec(t);
    if (!m) throw Object.assign(new Error('bad'), { status: 401 });
    return { sub: m[1], email: m[2], name: m[1] };
  },
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

const page = await call('GET', '/m/m_123');
assert.ok(String(page.body).includes('Live score'));

// ---- Player login ----
// Scorer 1 typed Ravi's number for p1; scorer 2 typed it for their own player q7.
assert.equal((await call('POST', '/v1/players/phones', { players: [{ id: 'p1', name: 'Ravi', team: 'A', phone: '+91 98765-43210' }, { id: 'p2', phone: '12' }] }, tok)).status, 200);
assert.equal((await call('POST', '/v1/players/phones', { players: [] })).status, 401, 'scorer must sign in');
const stored = db.prepare('SELECT phone_hash FROM player_phones').all();
assert.equal(stored.length, 1, 'short numbers are ignored');
assert.ok(!JSON.stringify(stored).includes('9876543210'), 'numbers are not stored as numbers');

assert.equal((await call('POST', '/v1/login', { idToken: 'fake' })).status, 401, 'bad google token');
const login = await call('POST', '/v1/login', { idToken: 'good:111:ravi@gmail.com' });
assert.equal(login.status, 200);
const ut = login.body.token;
assert.match(ut, /^U[A-Za-z0-9]+$/);
assert.equal(login.body.hasPhone, false);
assert.equal((await call('GET', '/v1/me')).status, 401);
assert.equal((await call('PUT', '/v1/me/phone', { phone: '123' }, ut)).status, 400);

let me = await call('PUT', '/v1/me/phone', { phone: '9876543210' }, ut);
assert.equal(me.status, 200);
assert.equal(me.body.hasPhone, true);
assert.deepEqual(me.body.profiles.map((x) => [x.name, x.status]), [['Ravi', 'pending']]);
assert.equal(me.body.matches.length, 0, 'nothing shown before the scorer says yes');

// Scorer 2 adds the same number later: a question appears for them too.
await call('POST', '/v1/players/phones', { players: [{ id: 'q7', name: 'Ravi K', phone: '09876543210' }] }, tok2);
assert.equal((await call('GET', '/v1/claims', undefined, tok2)).body.claims.length, 1);

const claims = await call('GET', '/v1/claims', undefined, tok);
assert.equal(claims.body.claims.length, 1);
assert.equal(claims.body.claims[0].email, 'ravi@gmail.com');
assert.equal(claims.body.claims[0].playerId, 'p1');
// Another scorer cannot answer for this one.
await call('POST', '/v1/claims', { userId: claims.body.claims[0].userId, playerId: 'p1', ok: true }, tok2);
assert.equal((await call('GET', '/v1/me', undefined, ut)).body.matches.length, 0);
await call('POST', '/v1/claims', { userId: claims.body.claims[0].userId, playerId: 'p1', ok: true }, tok);
me = await call('GET', '/v1/me', undefined, ut);
assert.equal(me.body.matches.length, 1);
assert.equal(me.body.matches[0].id, 'm_123');
assert.equal((await call('GET', '/v1/claims', undefined, tok)).body.claims.length, 0);

// Re-sending the same list keeps the "yes".
await call('POST', '/v1/players/phones', { players: [{ id: 'p1', name: 'Ravi', phone: '9876543210' }] }, tok);
assert.equal((await call('GET', '/v1/me', undefined, ut)).body.matches.length, 1);
// Same number typed again by the player keeps it too.
await call('PUT', '/v1/me/phone', { phone: '98765 43210' }, ut);
assert.equal((await call('GET', '/v1/me', undefined, ut)).body.matches.length, 1);

// Someone else logs in with Ravi's number: they only get a question, which the scorer can refuse.
const sneaky = (await call('POST', '/v1/login', { idToken: 'good:222:other@gmail.com' })).body.token;
await call('PUT', '/v1/me/phone', { phone: '9876543210' }, sneaky);
const q = (await call('GET', '/v1/claims', undefined, tok)).body.claims;
assert.equal(q.length, 1);
assert.equal(q[0].email, 'other@gmail.com');
await call('POST', '/v1/claims', { userId: q[0].userId, playerId: 'p1', ok: false }, tok);
assert.equal((await call('GET', '/v1/me', undefined, sneaky)).body.matches.length, 0);

// Scorer changes the player's number: the old link goes away.
await call('POST', '/v1/players/phones', { players: [{ id: 'p1', name: 'Ravi', phone: '9000000000' }] }, tok);
assert.equal((await call('GET', '/v1/me', undefined, ut)).body.matches.length, 0);
assert.equal((await call('GET', '/v1/me', undefined, ut)).body.profiles.length, 1, 'scorer 2 question is still there');

// On the scorer's own phone, their own players need no question.
await call('POST', '/v1/players/phones', { players: [{ id: 'p1', name: 'Ravi', phone: '9876543210' }] }, tok);
const own = (await call('POST', '/v1/login', { idToken: 'good:333:scorer@gmail.com' })).body.token;
me = await call('PUT', '/v1/me/phone', { phone: '9876543210', scorer: tok }, own);
assert.equal(me.body.matches.length, 1, 'own player auto-approved');
await call('PUT', '/v1/me/phone', { phone: '9876543210', scorer: reg.body.scorerId + '.wrong' }, sneaky);

// Logging out ends that phone's session only.
assert.equal((await call('DELETE', '/v1/me', undefined, own)).status, 200);
assert.equal((await call('GET', '/v1/me', undefined, own)).status, 401);
assert.equal((await call('GET', '/v1/me', undefined, ut)).status, 200);
assert.equal((await call('GET', '/v1/health')).body.login, false);

assert.equal((await call('DELETE', '/v1/matches/m_123', undefined, tok2)).status, 403);
assert.equal((await call('DELETE', '/v1/matches/m_123', undefined, tok)).status, 200);
assert.equal((await call('GET', '/v1/matches/m_123')).status, 404);
assert.equal((await call('GET', '/v1/players/p1/matches')).body.matches.length, 0);

const big = await call('PUT', '/v1/matches/m_big', { data: { x: 'a'.repeat(700 * 1024) }, summary }, tok);
assert.equal(big.status, 413);
console.log('server tests passed');
