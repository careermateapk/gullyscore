// Checks the live service end to end, then cleans up after itself.
// Usage: node test/smoke.mjs https://gullyscore-api.<name>.workers.dev
import assert from 'node:assert/strict';

const base = process.argv[2].replace(/\/+$/, '');
const call = async (method, path, body, token) => {
  const r = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  let json = null;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: r.status, body: json };
};

const reg = await call('POST', '/v1/register');
assert.equal(reg.status, 200, 'register');
const tok = reg.body.scorerId + '.' + reg.body.token;
const id = 'smoketest_' + Date.now();
const summary = { title: 'Smoke XI vs Test XI', status: 'Self check', finished: false, innings: [{ team: 'Smoke XI', score: '10/0', overs: '1.0', extras: '0', batting: [], bowling: [], fow: [] }], thisOver: ['4', '6'] };
assert.equal((await call('PUT', '/v1/matches/' + id, { data: { match: { id } }, summary, players: ['smoke_player'], finished: false }, tok)).status, 200, 'upload');
const got = await call('GET', '/v1/matches/' + id);
assert.equal(got.status, 200, 'read back');
assert.equal(got.body.summary.status, 'Self check');
const page = await call('GET', '/m/' + id);
assert.equal(page.status, 200, 'web page');
const list = await call('GET', '/v1/players/smoke_player/matches');
assert.ok(list.body.matches.some((m) => m.id === id), 'player list');
assert.equal((await call('DELETE', '/v1/matches/' + id, undefined, tok)).status, 200, 'delete');
assert.equal((await call('GET', '/v1/matches/' + id)).status, 404, 'gone');
for (const path of ['/privacy', '/terms', '/blog', '/v1/feed?kind=live', '/v1/leaderboard', '/v1/posts']) {
  assert.equal((await call('GET', path)).status, 200, path);
}
// Grounds from the free map (a warning only: the map service can be busy).
const dres = await fetch(base + '/v1/grounds?lat=28.6139&lng=77.2090&km=15');
const delhi = { status: dres.status, body: await dres.json() };
console.log('::notice::Map lookup: ' + (dres.headers.get('x-map') || '(none)'));
assert.equal(delhi.status, 200, 'grounds');
if (delhi.body.total > 0) console.log(`::notice::Map grounds near New Delhi: ${delhi.body.total} (e.g. ${delhi.body.grounds.slice(0, 5).map((g) => g.name).join(', ')})`);
else console.log('::warning::No map grounds near New Delhi yet (map service busy?)');
console.log('Live service works end to end');
