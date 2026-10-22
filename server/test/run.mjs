// Runs the Worker against a real SQLite database (node:sqlite) to check the API.
// Usage: node --experimental-sqlite test/run.mjs
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import assert from 'node:assert/strict';
import worker from '../src/index.js';

const db = new DatabaseSync(':memory:');
for (const f of readdirSync(new URL('../migrations/', import.meta.url)).filter((x) => x.endsWith('.sql')).sort()) db.exec(readFileSync(new URL('../migrations/' + f, import.meta.url), 'utf8'));

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
const stored = db.prepare("SELECT phone_hash FROM player_phones WHERE phone_hash != ''").all();
assert.equal(stored.length, 1, 'short numbers are not matched');
assert.equal(db.prepare('SELECT COUNT(*) AS n FROM player_phones').get().n, 2, 'players without a number stay in the squad');
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
assert.deepEqual(me.body.profiles.map((x) => [x.name, x.status]), [['Ravi', 'ok']]);
assert.equal(me.body.matches.length, 1, 'matches show at once, no approval needed');
assert.equal(me.body.matches[0].id, 'm_123');

// Scorer 2 adds the same number later: linked at once too.
await call('POST', '/v1/players/phones', { players: [{ id: 'q7', name: 'Ravi K', phone: '09876543210' }] }, tok2);
assert.equal((await call('GET', '/v1/me', undefined, ut)).body.profiles.length, 2);

// The scorer sees who is linked and can remove someone.
const linked = await call('GET', '/v1/claims', undefined, tok);
assert.equal(linked.body.claims.length, 1);
assert.equal(linked.body.claims[0].email, 'ravi@gmail.com');
assert.equal(linked.body.claims[0].playerId, 'p1');
// Another scorer cannot remove it.
await call('POST', '/v1/claims', { userId: linked.body.claims[0].userId, playerId: 'p1', ok: false }, tok2);
assert.equal((await call('GET', '/v1/me', undefined, ut)).body.matches.length, 1);

// Re-sending the same list / re-typing the same number keeps the link.
await call('POST', '/v1/players/phones', { players: [{ id: 'p1', name: 'Ravi', phone: '9876543210' }] }, tok);
await call('PUT', '/v1/me/phone', { phone: '98765 43210' }, ut);
assert.equal((await call('GET', '/v1/me', undefined, ut)).body.matches.length, 1);

// A second account with the same number is linked too; the scorer removes it.
const sneaky = (await call('POST', '/v1/login', { idToken: 'good:222:other@gmail.com' })).body.token;
await call('PUT', '/v1/me/phone', { phone: '9876543210' }, sneaky);
assert.equal((await call('GET', '/v1/me', undefined, sneaky)).body.matches.length, 1);
const two = (await call('GET', '/v1/claims', undefined, tok)).body.claims;
const other2 = two.find((c) => c.email === 'other@gmail.com');
await call('POST', '/v1/claims', { userId: other2.userId, playerId: 'p1', ok: false }, tok);
assert.equal((await call('GET', '/v1/me', undefined, sneaky)).body.matches.length, 0);
await call('PUT', '/v1/me/phone', { phone: '9876543210' }, sneaky);
assert.equal((await call('GET', '/v1/me', undefined, sneaky)).body.matches.length, 0, 'removed stays removed');
assert.equal((await call('GET', '/v1/claims', undefined, tok)).body.claims.length, 1);

// Scorer changes the player's number: the old link goes away.
await call('POST', '/v1/players/phones', { players: [{ id: 'p1', name: 'Ravi', phone: '9000000000' }] }, tok);
assert.equal((await call('GET', '/v1/me', undefined, ut)).body.matches.length, 0);
assert.equal((await call('GET', '/v1/me', undefined, ut)).body.profiles.length, 1, 'scorer 2 link is still there');

const own = (await call('POST', '/v1/login', { idToken: 'good:333:scorer@gmail.com' })).body.token;

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

// ================= v0.5: feed, My Cricket, leaderboard, community, ratings =================
{
  const s1 = await call('POST', '/v1/register');
  const sc = s1.body.scorerId + '.' + s1.body.token;
  const sum = (t, st) => ({ title: t, status: st, innings: [], thisOver: [] });
  const now = Date.now();
  // Live match: DD (p_a1, p_a2) vs GB (p_b1)
  await call('PUT', '/v1/matches/live1', {
    data: {}, summary: sum('DD vs GB', 'GB need 10'), finished: false, status: 'live', ground: 'Gaziabad',
    teamA: { id: 'tDD', name: 'Delhi Daredevils' }, teamB: { id: 'tGB', name: 'Gaziabad Bulldozers' },
    players: [
      { id: 'p_a1', team: 'tDD', name: 'Suraj', runs: 58, wickets: 0, line: { r: 58, b: 31, notOut: true } },
      { id: 'p_a2', team: 'tDD', name: 'Ravi', runs: 4, wickets: 2 },
      { id: 'p_b1', team: 'tGB', name: 'Amit', runs: 12, wickets: 1 },
    ],
  }, sc);
  // Finished match DD beat PT
  await call('PUT', '/v1/matches/res1', {
    data: {}, summary: sum('DD vs PT', 'DD won by 24 runs'), finished: true, status: 'result', winner: 'tDD',
    teamA: { id: 'tDD', name: 'Delhi Daredevils' }, teamB: { id: 'tPT', name: 'Pandaul Tigers' },
    players: [
      { id: 'p_a1', team: 'tDD', name: 'Suraj', runs: 75, wickets: 2, line: { r: 75, b: 38, notOut: true } },
      { id: 'p_c1', team: 'tPT', name: 'Mohan', runs: 30, wickets: 3 },
    ],
  }, sc);
  // Upcoming DD vs SK tomorrow
  await call('PUT', '/v1/matches/up1', {
    data: {}, summary: sum('DD vs SK', 'Tomorrow'), finished: false, status: 'upcoming', scheduled: now + 20 * 3600e3, ground: 'Rajnagar',
    teamA: { id: 'tDD', name: 'Delhi Daredevils' }, teamB: { id: 'tSK', name: 'Sakri Kings' },
    players: [{ id: 'p_a1', team: 'tDD', name: 'Suraj' }],
  }, sc);
  // Old app format still works.
  assert.equal((await call('PUT', '/v1/matches/old1', { data: {}, summary: sum('x', 'y'), players: ['zz'] }, sc)).status, 200);

  let f = await call('GET', '/v1/feed?kind=live');
  assert.ok(f.body.matches.some((x) => x.id === 'live1'));
  assert.equal(f.body.matches.find((x) => x.id === 'live1').ground, 'Gaziabad');
  assert.ok(!f.body.matches.some((x) => x.id === 'res1' || x.id === 'up1'));
  f = await call('GET', '/v1/feed?kind=upcoming');
  assert.deepEqual(f.body.matches.map((x) => x.id), ['up1']);
  assert.ok(f.body.counts.live >= 1 && f.body.counts.upcoming === 1);
  f = await call('GET', '/v1/feed?kind=results');
  assert.equal(f.body.matches[0].id, 'res1');
  assert.equal(f.body.matches[0].winner, 'tDD');

  // Suraj logs in with his number; scorer had typed it for p_a1 in team tDD.
  await call('POST', '/v1/players/phones', { players: [{ id: 'p_a1', name: 'Suraj', team: 'Delhi Daredevils', teamId: 'tDD', phone: '9111111111' }] }, sc);
  const su = (await call('POST', '/v1/login', { idToken: 'good:suraj:suraj@gmail.com' })).body.token;
  const me = (await call('PUT', '/v1/me/phone', { phone: '9111111111' }, su)).body;
  assert.equal(me.matches.length, 3, 'live, result and upcoming');
  assert.equal(me.matches.find((x) => x.id === 'live1').me.r, 58);
  assert.equal(me.totals.matches, 2, 'upcoming not counted');
  assert.equal(me.totals.runs, 133);
  assert.equal(me.totals.wickets, 2);
  assert.equal(me.totals.best, 75);
  assert.equal(me.totals.bestNotOut, true);
  assert.equal(me.teams.length, 1);
  const dd = me.teams[0];
  assert.equal(dd.name, 'Delhi Daredevils');
  assert.equal(dd.played, 1);
  assert.equal(dd.won, 1);
  assert.deepEqual(dd.form, ['W']);
  assert.equal(dd.next.id, 'up1');
  const teamPage = await call('GET', '/v1/teams/' + s1.body.scorerId + '/tDD');
  assert.equal(teamPage.body.matches.length, 3);

  // Leaderboard
  let lb = await call('GET', '/v1/leaderboard?kind=runs');
  assert.equal(lb.body.players[0].name, 'Suraj');
  assert.equal(lb.body.players[0].runs, 133);
  assert.equal(lb.body.players[0].team, 'Delhi Daredevils');
  lb = await call('GET', '/v1/leaderboard?kind=wickets');
  assert.equal(lb.body.players[0].name, 'Mohan');

  // ----- Ratings -----
  // Mohan (PT) logs in; rates DD for the finished match.
  await call('POST', '/v1/players/phones', { players: [
    { id: 'p_a1', name: 'Suraj', team: 'Delhi Daredevils', teamId: 'tDD', phone: '9111111111' },
    { id: 'p_c1', name: 'Mohan', team: 'Pandaul Tigers', teamId: 'tPT', phone: '9222222222' },
  ] }, sc);
  const mo = (await call('POST', '/v1/login', { idToken: 'good:mohan:mohan@gmail.com' })).body.token;
  await call('PUT', '/v1/me/phone', { phone: '9222222222' }, mo);
  let t = await call('GET', '/v1/matches/res1/rating', undefined, mo);
  assert.equal(t.body.canRate, true);
  assert.equal(t.body.team.name, 'Delhi Daredevils');
  assert.equal((await call('GET', '/v1/matches/live1/rating', undefined, mo)).body.canRate, false, 'not his match');
  assert.equal((await call('GET', '/v1/matches/live1/rating', undefined, su)).body.reason, 'not finished');
  assert.equal((await call('POST', '/v1/matches/res1/rating', { fair: 5, behaviour: 4, ontime: 3, tags: ['sportsmen', 'bogus'], comment: 'Great match!' }, mo)).status, 200);
  assert.equal((await call('POST', '/v1/matches/res1/rating', { fair: 1, behaviour: 1, ontime: 1 }, mo)).status, 403, 'only once');
  // Suraj rates PT.
  await call('POST', '/v1/matches/res1/rating', { fair: 4, behaviour: 4, ontime: 4 }, su);
  let rp = await call('GET', '/v1/teams/' + s1.body.scorerId + '/tDD/ratings');
  assert.equal(rp.body.count, 1);
  assert.equal(rp.body.overall, 4);
  assert.equal(rp.body.tags.sportsmen, 1);
  assert.equal(rp.body.comments.length, 1);
  const cid = rp.body.comments[0].id;
  assert.equal(rp.body.comments[0].author.name, 'mohan');
  assert.equal(rp.body.comments[0].author.team, 'Pandaul Tigers');
  // Reactions: Suraj 👍, Mohan ❤️, Suraj switches to 🔥, then removes it.
  await call('POST', '/v1/comments/' + cid + '/react', { emoji: '👍' }, su);
  let c = (await call('POST', '/v1/comments/' + cid + '/react', { emoji: '❤️' }, mo)).body;
  assert.equal(c.reactions.length, 2);
  c = (await call('POST', '/v1/comments/' + cid + '/react', { emoji: '🔥' }, su)).body;
  assert.equal(c.myReaction, '🔥');
  assert.equal(c.reactions.reduce((a, x) => a + x.n, 0), 2);
  c = (await call('POST', '/v1/comments/' + cid + '/react', { emoji: '🔥' }, su)).body;
  assert.equal(c.myReaction, null);
  assert.equal((await call('POST', '/v1/comments/' + cid + '/react', { emoji: '💩' }, su)).body.myReaction, null, 'unknown emoji removes');
  // Replies: Suraj is a DD player → Team tag.
  const r1 = (await call('POST', '/v1/comments/' + cid + '/replies', { body: 'Thank you bhai!' }, su)).body;
  assert.equal(r1.isTeam, true);
  const r2 = (await call('POST', '/v1/comments/' + r1.id + '/replies', { body: 'Next time again' }, mo)).body;
  assert.equal(r2.isTeam, false);
  assert.equal(r2.parentId, cid, 'reply to a reply stays in the same thread');
  rp = await call('GET', '/v1/teams/' + s1.body.scorerId + '/tDD/ratings');
  assert.equal(rp.body.comments[0].replies, 2);
  assert.equal(rp.body.comments[0].firstReplies.length, 2);
  assert.equal((await call('GET', '/v1/comments/' + cid + '/replies')).body.replies.length, 2);
  assert.equal((await call('POST', '/v1/comments/' + cid + '/replies', { body: 'x' })).status, 401);
  assert.equal(me.teams[0].rating, null);
  assert.equal((await call('GET', '/v1/me', undefined, su)).body.teams[0].rating, 4);

  // Reports: three people hide a comment.
  const users = [];
  for (const n of ['a', 'b', 'c']) users.push((await call('POST', '/v1/login', { idToken: `good:rep${n}:${n}@x.com` })).body.token);
  for (const u of users) await call('POST', '/v1/reports', { kind: 'comment', id: r2.id, reason: 'rude' }, u);
  assert.equal((await call('GET', '/v1/comments/' + cid + '/replies')).body.replies.length, 1);

  // ----- Community -----
  assert.equal((await call('POST', '/v1/posts', { kind: 'players', body: 'Need 2' })).status, 401, 'login needed');
  const post = (await call('POST', '/v1/posts', { kind: 'players', body: 'Sunday 7 AM, need a bowler', place: 'Gaziabad', need: 2, contact: '+91 91111-11111' }, su)).body;
  assert.equal(post.mine, true);
  assert.equal(post.contact, '+919111111111');
  let list = (await call('GET', '/v1/posts')).body.posts;
  assert.equal(list[0].id, post.id);
  assert.equal(list[0].contact, undefined, 'number hidden from strangers');
  assert.equal(list[0].hasContact, true);
  const joined = (await call('POST', '/v1/posts/' + post.id + '/join', {}, mo)).body;
  assert.equal(joined.joined, true);
  assert.equal(joined.contact, '+919111111111', 'shown after joining');
  assert.equal(joined.joins, 1);
  const who = (await call('GET', '/v1/posts/' + post.id + '/joins', undefined, su)).body.joins;
  assert.equal(who[0].name, 'mohan');
  assert.equal((await call('GET', '/v1/posts/' + post.id + '/joins', undefined, mo)).status, 403);
  // Poll
  assert.equal((await call('POST', '/v1/posts', { kind: 'poll', body: 'Best batter?', options: ['Suraj'] }, su)).status, 400);
  const poll = (await call('POST', '/v1/posts', { kind: 'poll', body: 'Best batter?', options: ['Suraj', 'Ravi', 'Amit'] }, su)).body;
  await call('POST', '/v1/posts/' + poll.id + '/vote', { option: 0 }, mo);
  let pv = (await call('POST', '/v1/posts/' + poll.id + '/vote', { option: 2 }, su)).body;
  assert.deepEqual(pv.votes, [1, 0, 1]);
  pv = (await call('POST', '/v1/posts/' + poll.id + '/vote', { option: 1 }, su)).body;
  assert.deepEqual(pv.votes, [1, 1, 0], 'changing a vote');
  assert.equal(pv.myVote, 1);
  assert.equal((await call('POST', '/v1/posts/' + poll.id + '/vote', { option: 7 }, su)).status, 400);
  // Tournament with entry fee and paid tick.
  const tour = (await call('POST', '/v1/posts', { kind: 'tournament', body: 'MPL 2026, 8 teams', fee: 500, upi: 'mpl@upi', teams: 8, lastDate: '2026-10-28', prize: '₹5,000' }, su)).body;
  assert.equal(tour.extra.fee, 500);
  await call('POST', '/v1/posts/' + tour.id + '/join', { note: 'Pandaul Tigers' }, mo);
  const reg = (await call('GET', '/v1/posts/' + tour.id + '/joins', undefined, su)).body.joins[0];
  assert.equal(reg.note, 'Pandaul Tigers');
  await call('POST', '/v1/posts/' + tour.id + '/paid', { userId: reg.userId, paid: true }, su);
  assert.equal((await call('GET', '/v1/posts/' + tour.id + '/joins', undefined, su)).body.joins[0].paid, true);
  assert.equal((await call('GET', '/v1/posts?kind=poll')).body.posts.length, 1);
  // Only the author deletes.
  assert.equal((await call('DELETE', '/v1/posts/' + poll.id, undefined, mo)).status, 403);
  assert.equal((await call('DELETE', '/v1/posts/' + poll.id, undefined, su)).status, 200);

  // ----- Delete my account -----
  assert.equal((await call('DELETE', '/v1/me/account', undefined, mo)).status, 200);
  assert.equal((await call('GET', '/v1/me', undefined, mo)).status, 401);
  rp = await call('GET', '/v1/teams/' + s1.body.scorerId + '/tDD/ratings');
  assert.equal(rp.body.count, 0, 'his rating is gone');
  assert.equal(rp.body.comments.length, 0, 'his comment and its replies are gone');
  assert.equal((await call('GET', '/v1/posts/' + tour.id + '/joins', undefined, su)).body.joins.length, 0);

  // ----- Web pages -----
  for (const path of ['/', '/privacy', '/terms', '/about', '/blog', '/privacy?lang=hi', '/blog/score-your-first-match']) {
    const r = await call('GET', path);
    assert.equal(r.status, 200, path);
    assert.ok(String(r.body).includes('GullyScore'), path);
  }
  assert.ok(String((await call('GET', '/privacy?lang=hi')).body).includes('प्राइवेसी'));
  assert.equal((await call('GET', '/blog/nope')).status, 404);
}

// ================= v0.6: who is coming, team khata =================
{
  const s9 = await call('POST', '/v1/register');
  const sc = s9.body.scorerId + '.' + s9.body.token;
  const S = s9.body.scorerId;
  await call('POST', '/v1/players/phones', { players: [
    { id: 'k1', name: 'Kapil', team: 'Kings', teamId: 'tK', phone: '9333333331' },
    { id: 'k2', name: 'Kunal', team: 'Kings', teamId: 'tK', phone: '9333333332' },
    { id: 'k3', name: 'Kamal', team: 'Kings', teamId: 'tK' },
    { id: 'q1', name: 'Other', team: 'Queens', teamId: 'tQ', phone: '9333333339' },
  ] }, sc);
  const kapil = (await call('POST', '/v1/login', { idToken: 'good:kapil:kapil@x.com' })).body.token;
  await call('PUT', '/v1/me/phone', { phone: '9333333331' }, kapil);
  const kunal = (await call('POST', '/v1/login', { idToken: 'good:kunal:kunal@x.com' })).body.token;
  await call('PUT', '/v1/me/phone', { phone: '9333333332' }, kunal);
  const queen = (await call('POST', '/v1/login', { idToken: 'good:queen:q@x.com' })).body.token;
  await call('PUT', '/v1/me/phone', { phone: '9333333339' }, queen);

  // Who is coming?
  const base = '/v1/teams/' + S + '/tK';
  assert.equal((await call('POST', base + '/asks', { title: 'vs Sakri Kings' }, queen)).status, 403, 'other team');
  const ask = (await call('POST', base + '/asks', { title: 'vs Sakri Kings', when: 'Sunday 7 AM', place: 'Gaziabad', need: 11 }, kapil)).body;
  assert.equal(ask.players.length, 3, 'whole squad, even without a number');
  assert.equal(ask.waiting, 3);
  let a = (await call('POST', '/v1/asks/' + ask.id + '/answer', { answer: 'yes' }, kapil)).body;
  assert.equal(a.myAnswer, 'yes');
  a = (await call('POST', '/v1/asks/' + ask.id + '/answer', { answer: 'no' }, kunal)).body;
  assert.equal(a.yes, 1);
  assert.equal(a.no, 1);
  assert.equal(a.waiting, 1);
  a = (await call('POST', '/v1/asks/' + ask.id + '/answer', { answer: 'maybe' }, kunal)).body;
  assert.equal(a.no, 0, 'changing an answer');
  assert.equal((await call('POST', '/v1/asks/' + ask.id + '/answer', { answer: 'yes' }, queen)).status, 403);
  assert.equal((await call('GET', base + '/asks', undefined, kunal)).body.asks.length, 1);
  assert.equal((await call('DELETE', '/v1/asks/' + ask.id, undefined, kunal)).status, 403);

  // Khata: 900 balls (Kapil), 1500 ground (Kunal); 3 players → share 800.
  await call('POST', base + '/khata', { kind: 'expense', amount: 900, note: '2 balls', playerId: 'k1' }, kapil);
  let k = (await call('POST', base + '/khata', { kind: 'expense', amount: 1500, note: 'Ground', playerId: 'k2' }, kunal)).body;
  assert.equal(k.spent, 2400);
  assert.equal(k.share, 800);
  assert.equal(k.people.find((x) => x.playerId === 'k3').due, 800);
  assert.equal(k.people.find((x) => x.playerId === 'k1').due, 0, 'spent more than share');
  k = (await call('POST', base + '/khata', { kind: 'payment', amount: 300, playerId: 'k3' }, kapil)).body;
  assert.equal(k.people.find((x) => x.playerId === 'k3').due, 500);
  assert.equal(k.pending, 500);
  assert.equal((await call('POST', base + '/khata', { kind: 'expense', amount: 10, playerId: 'q1' }, kapil)).status, 400, 'not our player');
  assert.equal((await call('POST', base + '/khata', { kind: 'expense', amount: -5, playerId: 'k1' }, kapil)).status, 400);
  assert.equal((await call('GET', base + '/khata', undefined, queen)).status, 403);
  const pay = k.items.find((i) => i.kind === 'payment');
  assert.equal((await call('DELETE', '/v1/khata/' + pay.id, undefined, kunal)).status, 403);
  k = (await call('DELETE', '/v1/khata/' + pay.id, undefined, kapil)).body;
  assert.equal(k.pending, 800);
  assert.equal((await call('GET', base + '/khata?month=2020-01', undefined, kapil)).body.spent, 0);
}

// ================= v0.8: grounds =================
{
  env.NO_MAP = true;
  env.FAKE_PLACES = async (q) => [{ name: 'Darbhanga', detail: 'Bihar, India', lat: 26.15, lng: 85.9 }];
  assert.equal((await call('GET', '/v1/places?q=Darbh')).body.places[0].name, 'Darbhanga');
  assert.equal((await call('GET', '/v1/places?q=D')).body.places.length, 0);
  const u = (await call('POST', '/v1/login', { idToken: 'good:groundman:g@x.com' })).body.token;
  const v = (await call('POST', '/v1/login', { idToken: 'good:groundfan:f@x.com' })).body.token;
  assert.equal((await call('POST', '/v1/grounds', { name: 'X', lat: 1, lng: 2 })).status, 401);
  assert.equal((await call('POST', '/v1/grounds', { name: '', lat: 1, lng: 2 }, u)).status, 400);
  const g1 = (await call('POST', '/v1/grounds', {
    name: 'Rajnagar Stadium', address: 'Near bus stand', city: 'Madhubani', lat: 26.40, lng: 86.10,
    pitches: ['turf', 'lava'], facilities: ['lights', 'washrooms', 'jacuzzi'], feeMin: 1500, feeMax: 1000, boundaryMin: 55, boundaryMax: 70,
    timings: '6 AM - 10 PM', phone: '98765 43210',
  }, u)).body;
  assert.deepEqual(g1.pitches, ['turf']);
  assert.deepEqual(g1.facilities, ['lights', 'washrooms']);
  assert.equal(g1.feeMax, 1500, 'max is never below min');
  const g2 = (await call('POST', '/v1/grounds', { name: 'Sakri School', city: 'Sakri', lat: 26.30, lng: 86.05, pitches: ['matting'], feeMin: 0 }, u)).body;
  await call('POST', '/v1/grounds', { name: 'Patna Ground', lat: 25.6, lng: 85.1 }, u);

  let near = (await call('GET', '/v1/grounds?lat=26.35&lng=86.07&km=15')).body;
  assert.equal(near.total, 2, 'Patna is too far');
  assert.ok(near.grounds[0].km <= near.grounds[1].km, 'nearest first');
  near = (await call('GET', '/v1/grounds?lat=26.35&lng=86.07&km=15&pitch=turf')).body;
  assert.deepEqual(near.grounds.map((g) => g.name), ['Rajnagar Stadium']);
  near = (await call('GET', '/v1/grounds?lat=26.35&lng=86.07&km=15&fac=lights,washrooms')).body;
  assert.equal(near.total, 1);
  near = (await call('GET', '/v1/grounds?lat=26.35&lng=86.07&km=15&feeMax=1000')).body;
  assert.deepEqual(near.grounds.map((g) => g.name), ['Sakri School']);
  near = (await call('GET', '/v1/grounds?lat=26.35&lng=86.07&km=300&sort=name')).body;
  assert.deepEqual(near.grounds.map((g) => g.name), ['Patna Ground', 'Rajnagar Stadium', 'Sakri School']);
  assert.equal((await call('GET', '/v1/grounds?q=madhu')).body.grounds[0].name, 'Rajnagar Stadium', 'search by city');

  // Photos
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 0xff, 0xd9]).toString('base64');
  assert.equal((await call('POST', '/v1/grounds/' + g1.id + '/photos', { jpeg: 'aGVsbG8=' }, v)).status, 400, 'must be a JPEG');
  const ph = (await call('POST', '/v1/grounds/' + g1.id + '/photos', { jpeg }, v)).body;
  assert.ok(ph.id);
  const r = await worker.fetch(new Request('https://x.test/v1/grounds/' + g1.id + '/photos/' + ph.id), env);
  assert.equal(r.headers.get('content-type'), 'image/jpeg');
  assert.equal(Buffer.from(await r.arrayBuffer()).toString('base64'), jpeg);
  let d = (await call('GET', '/v1/grounds/' + g1.id + '?lat=26.35&lng=86.07', undefined, u)).body;
  assert.deepEqual(d.photoIds, [ph.id]);
  assert.equal(d.mine, true);
  assert.equal(d.photo, ph.id);
  assert.equal((await call('GET', '/v1/grounds/' + g1.id, undefined, v)).body.mine, false);
  // Owner of the ground can remove anyone's photo there.
  assert.equal((await call('DELETE', '/v1/grounds/' + g1.id + '/photos/' + ph.id, undefined, u)).status, 200);
  await call('POST', '/v1/grounds/' + g1.id + '/photos', { jpeg }, v);

  // Edit (owner only)
  assert.equal((await call('PUT', '/v1/grounds/' + g1.id, { feeMin: 2000 }, v)).status, 403);
  assert.equal((await call('PUT', '/v1/grounds/' + g1.id, { feeMin: 2000, feeMax: 2500 }, u)).body.feeMin, 2000);

  // Reviews
  await call('POST', '/v1/grounds/' + g1.id + '/reviews', { stars: 5, body: 'Great turf' }, v);
  await call('POST', '/v1/grounds/' + g1.id + '/reviews', { stars: 3 }, u);
  await call('POST', '/v1/grounds/' + g1.id + '/reviews', { stars: 4, body: 'Nice' }, u);
  d = (await call('GET', '/v1/grounds/' + g1.id)).body;
  assert.equal(d.reviews, 2, 'one review per person');
  assert.equal(d.rating, 4.5);
  assert.equal((await call('GET', '/v1/grounds/' + g1.id + '/reviews')).body.reviews.length, 2);

  // Matches at the ground → matches, tournaments, insights
  const s7 = await call('POST', '/v1/register');
  const sc = s7.body.scorerId + '.' + s7.body.token;
  const mk = (id, a, b, sa, sb, winner) =>
    call('PUT', '/v1/matches/' + id, {
      data: {}, title: 'MPL 2026', status: 'result', finished: true, groundId: g1.id, winner,
      teamA: { id: 'ta', name: a }, teamB: { id: 'tb', name: b },
      summary: { title: a + ' vs ' + b, status: 'done', innings: [{ team: a, score: sa, overs: '10.0' }, { team: b, score: sb, overs: '10.0' }] },
      players: [{ id: 'pp1', team: 'ta', name: 'Suraj', runs: 70, wickets: 1 }, { id: 'pp2', team: 'tb', name: 'Amit', runs: 5, wickets: 3 }],
    }, sc);
  await mk('gm1', 'Kings', 'Tigers', '150/4', '120/9', 'ta');
  await mk('gm2', 'Kings', 'Tigers', '90/9', '91/2', 'tb');
  d = (await call('GET', '/v1/grounds/' + g1.id)).body;
  assert.equal(d.matches, 2);
  const gm = (await call('GET', '/v1/grounds/' + g1.id + '/matches')).body;
  assert.equal(gm.matches.length, 2);
  assert.deepEqual(gm.tournaments.map((t) => [t.title, t.matches]), [['MPL 2026', 2]]);
  const ins = (await call('GET', '/v1/grounds/' + g1.id + '/insights')).body;
  assert.equal(ins.matches, 2);
  assert.equal(ins.avgFirst, 120);
  assert.equal(ins.highest.runs, 150);
  assert.equal(ins.lowest.runs, 90);
  assert.equal(ins.batFirstWinPct, 50);
  assert.equal(ins.topRuns[0].name, 'Suraj');
  assert.equal(ins.topRuns[0].value, 140);
  assert.equal(ins.topWickets[0].name, 'Amit');
  assert.equal(ins.days.reduce((a, b) => a + b, 0), 2);
  assert.equal((await call('GET', '/v1/grounds/nope')).status, 404);
  delete env.FAKE_PLACES;
  delete env.NO_MAP;
}

// ================= v0.9: grounds from the map =================
{
  let lookups = 0;
  env.FAKE_OVERPASS = async () => {
    lookups++;
    return [
      { type: 'way', id: 11, center: { lat: 28.6, lon: 77.2 }, tags: { leisure: 'pitch', sport: 'cricket', name: 'Siri Fort Cricket Ground', surface: 'grass', lit: 'yes' } },
      { type: 'node', id: 12, lat: 28.61, lon: 77.21, tags: { leisure: 'stadium', sport: 'cricket;football', name: 'Delhi Stadium', 'addr:city': 'New Delhi' } },
      { type: 'node', id: 13, lat: 28.6, lon: 77.2, tags: { shop: 'sports', sport: 'cricket', name: 'Cricket Bats Shop' } },
      { type: 'way', id: 14, center: { lat: 28.6, lon: 77.2 }, tags: { leisure: 'pitch', sport: 'cricket' } },
      { type: 'way', id: 15, center: { lat: 28.62, lon: 77.2 }, tags: { leisure: 'pitch', sport: 'football', name: 'Football Field' } },
      { type: 'node', id: 16, lat: 28.6, lon: 77.19, tags: { club: 'sport', sport: 'cricket', name: 'Push Sports Cricket Academy', phone: '+91 98100 00000' } },
    ];
  };
  let near = (await call('GET', '/v1/grounds?lat=28.6&lng=77.2&km=15')).body;
  assert.deepEqual(near.grounds.map((g) => g.name).sort(), ['Delhi Stadium', 'Push Sports Cricket Academy', 'Siri Fort Cricket Ground']);
  const siri = near.grounds.find((g) => g.name.startsWith('Siri'));
  assert.equal(siri.fromMap, true);
  assert.deepEqual(siri.pitches, ['turf']);
  assert.deepEqual(siri.facilities, ['lights']);
  near = (await call('GET', '/v1/grounds?lat=28.6&lng=77.2&km=15')).body;
  assert.equal(near.total, 3, 'no duplicates');
  assert.equal(lookups, 1, 'area cached');
  // Anyone signed in can fill a map ground's details; then it is theirs.
  const a = (await call('POST', '/v1/login', { idToken: 'good:mapper:m@x.com' })).body.token;
  const b = (await call('POST', '/v1/login', { idToken: 'good:mapper2:m2@x.com' })).body.token;
  assert.equal((await call('PUT', '/v1/grounds/' + siri.id, { feeMin: 1500, feeMax: 2000 })).status, 401);
  assert.equal((await call('PUT', '/v1/grounds/' + siri.id, { feeMin: 1500, feeMax: 2000 }, a)).body.feeMin, 1500);
  assert.equal((await call('GET', '/v1/grounds/' + siri.id, undefined, a)).body.mine, true);
  assert.equal((await call('GET', '/v1/grounds/' + siri.id)).body.fromMap, false);
  assert.equal((await call('PUT', '/v1/grounds/' + siri.id, { feeMin: 1 }, b)).status, 403);
  // Map down: still answers with what we have.
  env.FAKE_OVERPASS = async () => null;
  assert.equal((await call('GET', '/v1/grounds?lat=19.07&lng=72.87&km=15')).body.total, 0);
  delete env.FAKE_OVERPASS;
  env.NO_MAP = true;
}

// ================= v0.7: notifications =================
{
  const sent = [];
  env.FAKE_PUSH = (m) => sent.push(m);
  const s1 = await call('POST', '/v1/register');
  const sc = s1.body.scorerId + '.' + s1.body.token;
  const S = s1.body.scorerId;
  const inn = (score, overs, batting) => ({ team: 'DD', score, overs, extras: '0', batting, bowling: [], fow: [] });
  const put = (status, innings, extra = {}) =>
    call('PUT', '/v1/matches/nm1', { data: {}, summary: { title: 'DD vs GB', status: 'DD won by 5 runs', innings, thisOver: [] }, status, teamA: { id: 'tDD', name: 'DD' }, teamB: { id: 'tGB', name: 'GB' }, ...extra }, sc);
  await put('upcoming', [], { scheduled: Date.now() + 3600e3 });
  assert.equal(sent.length, 0, 'scheduling is quiet');
  await put('live', [inn('0/0', '0.0', [])]);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].notification.title, '🏏 Match started');
  assert.ok(sent[0].condition.includes("'m.nm1.s' in topics"));
  assert.ok(sent[0].condition.includes(`'t.${S}.tDD.s' in topics`));
  sent.length = 0;
  await put('live', [inn('46/0', '4.0', [{ name: 'Suraj', r: 46, b: 20, '4s': 5, '6s': 2 }])]);
  await put('live', [inn('52/1', '4.3', [{ name: 'Suraj', r: 52, b: 22, '4s': 5, '6s': 3 }])]);
  const titles = sent.map((x) => x.notification.title);
  assert.ok(titles.includes('🔴 WICKET!'));
  assert.ok(titles.includes('⭐ Suraj reaches 50!'));
  assert.ok(titles.includes('💥 SIX! Suraj'));
  assert.ok(sent.find((x) => x.notification.title === '💥 SIX! Suraj').condition.includes("'m.nm1.b'"));
  sent.length = 0;
  await put('result', [inn('52/1', '5.0', [{ name: 'Suraj', r: 52, b: 22, '4s': 5, '6s': 3 }])], { finished: true });
  assert.deepEqual(sent.map((x) => x.notification.title), ['🏆 Result']);
  sent.length = 0;
  await put('result', [inn('52/1', '5.0', [])], { finished: true });
  assert.equal(sent.length, 0, 'result only once');

  // Community join, reply, reaction go to the person's own topic.
  const a = (await call('POST', '/v1/login', { idToken: 'good:pa:pa@x.com' })).body;
  const b = (await call('POST', '/v1/login', { idToken: 'good:pb:pb@x.com' })).body;
  assert.equal(a.id, 'gpa');
  const post = (await call('POST', '/v1/posts', { kind: 'players', body: 'Need 1' }, a.token)).body;
  sent.length = 0;
  await call('POST', '/v1/posts/' + post.id + '/join', {}, b.token);
  assert.equal(sent[0].topic, 'u.gpa');
  await call('POST', '/v1/posts/' + post.id + '/join', {}, b.token);
  assert.equal(sent.length, 1, 'joining twice notifies once');
  await call('POST', '/v1/posts/' + post.id + '/join', {}, a.token);
  assert.equal(sent.length, 1, 'own post is quiet');
  delete env.FAKE_PUSH;
}

console.log('server tests passed');
