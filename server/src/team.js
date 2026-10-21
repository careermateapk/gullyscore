// v0.6: team tools for logged-in players of a team: "Who is coming?" and
// the team khata. A person belongs to a team when a scorer typed their
// mobile number for a player of that team.
import { push, topic } from './push.js';
import { HttpError, ID_RE, TOKEN_ALPHABET, json, randomString, readJson, userAuth } from './util.js';

const str = (v, n) => (typeof v === 'string' ? v.trim().slice(0, n) : '');
const ANSWERS = ['yes', 'no', 'maybe'];

/** The player id this user has in that team, or throws 403. */
async function memberOf(env, user, scorerId, teamId) {
  const row = await env.DB.prepare(
    `SELECT pp.player_id, pp.name FROM claims c JOIN player_phones pp ON pp.scorer_id = c.scorer_id AND pp.player_id = c.player_id
     WHERE c.user_id = ? AND c.status = 'ok' AND pp.scorer_id = ? AND pp.team_id = ? LIMIT 1`,
  ).bind(user.id, scorerId, teamId).first();
  if (!row) throw new HttpError(403, 'not in this team');
  return row;
}

async function squad(env, scorerId, teamId) {
  const rows = await env.DB.prepare('SELECT player_id, name FROM player_phones WHERE scorer_id = ? AND team_id = ? ORDER BY name').bind(scorerId, teamId).all();
  return rows.results || [];
}

async function askView(env, a, me) {
  const players = await squad(env, a.scorer_id, a.team_id);
  const replies = await env.DB.prepare('SELECT player_id, answer FROM ask_replies WHERE ask_id = ?').bind(a.id).all();
  const by = Object.fromEntries((replies.results || []).map((r) => [r.player_id, r.answer]));
  const list = players.map((p) => ({ playerId: p.player_id, name: p.name, answer: by[p.player_id] || '' }));
  const count = (x) => list.filter((p) => p.answer === x).length;
  return {
    id: a.id,
    title: a.title,
    when: a.when_text,
    place: a.place,
    need: a.need,
    created: a.created,
    mine: a.user_id === me.user.id,
    myAnswer: by[me.playerId] || '',
    yes: count('yes'),
    no: count('no'),
    maybe: count('maybe'),
    waiting: list.filter((p) => !p.answer).length,
    players: list,
  };
}

function monthOf(t = Date.now()) {
  const d = new Date(t + 5.5 * 3600 * 1000); // India time
  return d.toISOString().slice(0, 7);
}

async function khataView(env, scorerId, teamId, month) {
  const items = await env.DB.prepare('SELECT * FROM khata WHERE scorer_id = ? AND team_id = ? AND month = ? ORDER BY created DESC')
    .bind(scorerId, teamId, month)
    .all();
  const players = await squad(env, scorerId, teamId);
  const names = Object.fromEntries(players.map((p) => [p.player_id, p.name]));
  const list = items.results || [];
  const spent = list.filter((i) => i.kind === 'expense').reduce((a, i) => a + i.amount, 0);
  const n = players.length || 1;
  const share = Math.ceil(spent / n);
  const gave = {};
  for (const i of list) gave[i.player_id] = (gave[i.player_id] || 0) + i.amount;
  const people = players.map((p) => ({ playerId: p.player_id, name: p.name, paid: gave[p.player_id] || 0, due: Math.max(0, share - (gave[p.player_id] || 0)) }));
  return {
    month,
    spent,
    share,
    players: n,
    pending: people.reduce((a, p) => a + p.due, 0),
    people,
    items: list.map((i) => ({ id: i.id, kind: i.kind, amount: i.amount, note: i.note, playerId: i.player_id, name: names[i.player_id] || '', created: i.created })),
  };
}

export async function teamRoutes(p, method, url, request, env) {
  let m;
  // ----- Who is coming? -----
  if ((m = /^\/v1\/teams\/([^/]+)\/([^/]+)\/asks$/.exec(p))) {
    const [, scorerId, teamId] = m;
    if (!ID_RE.test(scorerId) || !ID_RE.test(teamId)) throw new HttpError(400, 'bad id');
    const user = await userAuth(request, env);
    const me = await memberOf(env, user, scorerId, teamId);
    const ctx = { user, playerId: me.player_id };
    if (method === 'GET') {
      const rows = await env.DB.prepare('SELECT * FROM asks WHERE scorer_id = ? AND team_id = ? ORDER BY created DESC LIMIT 10').bind(scorerId, teamId).all();
      const asks = [];
      for (const a of rows.results || []) asks.push(await askView(env, a, ctx));
      return json({ asks });
    }
    if (method === 'POST') {
      const b = await readJson(request);
      const title = str(b?.title, 120);
      if (!title) throw new HttpError(400, 'missing title');
      const id = randomString(14, TOKEN_ALPHABET);
      const need = Math.max(1, Math.min(30, Math.trunc(Number(b?.need) || 11)));
      await env.DB.prepare('INSERT INTO asks (id, scorer_id, team_id, title, when_text, place, need, user_id, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
        .bind(id, scorerId, teamId, title, str(b?.when, 60), str(b?.place, 80), need, user.id, Date.now())
        .run();
      const a = await env.DB.prepare('SELECT * FROM asks WHERE id = ?').bind(id).first();
      await push(env, [topic('t', scorerId, teamId, 'a')], `🙋 ${title}: are you coming?`, [str(b?.when, 60), str(b?.place, 80)].filter(Boolean).join(' · ') || 'Answer in GullyScore', { ask: id });
      return json(await askView(env, a, ctx));
    }
  }

  if ((m = /^\/v1\/asks\/([A-Za-z0-9]+)(\/answer)?$/.exec(p))) {
    const user = await userAuth(request, env);
    const a = await env.DB.prepare('SELECT * FROM asks WHERE id = ?').bind(m[1]).first();
    if (!a) throw new HttpError(404, 'no such question');
    const me = await memberOf(env, user, a.scorer_id, a.team_id);
    const ctx = { user, playerId: me.player_id };
    if (m[2] && method === 'POST') {
      const b = await readJson(request);
      const answer = ANSWERS.includes(b?.answer) ? b.answer : null;
      if (!answer) throw new HttpError(400, 'bad answer');
      await env.DB.prepare(
        'INSERT INTO ask_replies (ask_id, player_id, answer, user_id, updated) VALUES (?, ?, ?, ?, ?) ON CONFLICT(ask_id, player_id) DO UPDATE SET answer = excluded.answer, user_id = excluded.user_id, updated = excluded.updated',
      ).bind(a.id, me.player_id, answer, user.id, Date.now()).run();
      return json(await askView(env, a, ctx));
    }
    if (!m[2] && method === 'DELETE') {
      if (a.user_id !== user.id) throw new HttpError(403, 'not yours');
      await env.DB.batch([env.DB.prepare('DELETE FROM ask_replies WHERE ask_id = ?').bind(a.id), env.DB.prepare('DELETE FROM asks WHERE id = ?').bind(a.id)]);
      return json({ ok: true });
    }
  }

  // ----- Team khata -----
  if ((m = /^\/v1\/teams\/([^/]+)\/([^/]+)\/khata$/.exec(p))) {
    const [, scorerId, teamId] = m;
    if (!ID_RE.test(scorerId) || !ID_RE.test(teamId)) throw new HttpError(400, 'bad id');
    const user = await userAuth(request, env);
    await memberOf(env, user, scorerId, teamId);
    if (method === 'GET') {
      const month = /^\d{4}-\d{2}$/.test(url.searchParams.get('month') || '') ? url.searchParams.get('month') : monthOf();
      return json(await khataView(env, scorerId, teamId, month));
    }
    if (method === 'POST') {
      const b = await readJson(request);
      const kind = b?.kind === 'payment' ? 'payment' : b?.kind === 'expense' ? 'expense' : null;
      const amount = Math.trunc(Number(b?.amount) || 0);
      const playerId = str(b?.playerId, 80);
      if (!kind || amount <= 0 || amount > 1000000 || !playerId) throw new HttpError(400, 'missing');
      const inTeam = await env.DB.prepare('SELECT 1 FROM player_phones WHERE scorer_id = ? AND team_id = ? AND player_id = ?').bind(scorerId, teamId, playerId).first();
      if (!inTeam) throw new HttpError(400, 'not a player of this team');
      const month = /^\d{4}-\d{2}$/.test(b?.month || '') ? b.month : monthOf();
      await env.DB.prepare('INSERT INTO khata (id, scorer_id, team_id, month, kind, amount, note, player_id, user_id, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
        .bind(randomString(14, TOKEN_ALPHABET), scorerId, teamId, month, kind, amount, str(b?.note, 80), playerId, user.id, Date.now())
        .run();
      return json(await khataView(env, scorerId, teamId, month));
    }
  }

  if ((m = /^\/v1\/khata\/([A-Za-z0-9]+)$/.exec(p)) && method === 'DELETE') {
    const user = await userAuth(request, env);
    const row = await env.DB.prepare('SELECT * FROM khata WHERE id = ?').bind(m[1]).first();
    if (!row) return json({ ok: true });
    if (row.user_id !== user.id) throw new HttpError(403, 'only who added it can remove it');
    await env.DB.prepare('DELETE FROM khata WHERE id = ?').bind(m[1]).run();
    return json(await khataView(env, row.scorer_id, row.team_id, row.month));
  }

  return null;
}

export async function deleteUserTeamData(env, userId) {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM ask_replies WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM ask_replies WHERE ask_id IN (SELECT id FROM asks WHERE user_id = ?)').bind(userId),
    env.DB.prepare('DELETE FROM asks WHERE user_id = ?').bind(userId),
  ]);
}
