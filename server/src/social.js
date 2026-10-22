// v0.5: all-matches feed, My Cricket, leaderboard, community posts,
// ratings with comments, reactions and replies, reports, account deletion.
import { deleteUserTeamData } from './team.js';
import { push, topic } from './push.js';
import { HttpError, ID_RE, TOKEN_ALPHABET, auth, json, photoKey, randomString, readJson, userAuth } from './util.js';

const HOUR = 3600 * 1000;
const LIVE_FOR = 6 * HOUR; // a "live" match not updated for 6 hours drops off the live list
const HIDE_AFTER_REPORTS = 3;

const str = (v, n) => (typeof v === 'string' ? v.trim().slice(0, n) : '');
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, Math.trunc(Number(v) || 0)));
const parse = (t, d) => {
  try {
    return JSON.parse(t);
  } catch {
    return d;
  }
};

/** One match in a list (feed, My Cricket, team pages). */
export function matchItem(r) {
  return {
    id: r.id,
    updated: r.updated,
    finished: !!r.finished,
    title: r.title || '',
    status: r.status || (r.finished ? 'result' : 'live'),
    scheduled: r.scheduled ?? null,
    ground: r.ground || '',
    teamA: { id: r.team_a || '', name: r.team_a_name || '' },
    teamB: { id: r.team_b || '', name: r.team_b_name || '' },
    winner: r.winner || '',
    summary: parse(r.summary, {}),
  };
}

const MATCH_COLS = 'm.id, m.updated, m.finished, m.title, m.summary, m.status, m.scheduled, m.ground, m.team_a, m.team_b, m.team_a_name, m.team_b_name, m.winner, m.scorer_id';

/** My matches (with my numbers in each), my teams (form, next match) and my totals. */
export async function myCricket(user, env) {
  const rows = await env.DB.prepare(
    `SELECT ${MATCH_COLS}, mp.player_id, mp.team AS my_team, mp.runs, mp.wickets, mp.line FROM claims c
     JOIN match_players mp ON mp.player_id = c.player_id
     JOIN matches m ON m.id = mp.match_id AND m.scorer_id = c.scorer_id
     WHERE c.user_id = ? AND c.status = 'ok' ORDER BY COALESCE(m.scheduled, m.updated) DESC LIMIT 200`,
  ).bind(user.id).all();
  const seen = new Set();
  const matches = [];
  const totals = { matches: 0, runs: 0, wickets: 0, best: 0, bestNotOut: false };
  for (const r of rows.results || []) {
    if (seen.has(r.id)) continue;
    seen.add(r.id);
    const line = parse(r.line, {});
    matches.push({ ...matchItem(r), me: { playerId: r.player_id, team: r.my_team || '', ...line } });
    if ((r.status || 'live') === 'upcoming') continue;
    totals.matches++;
    totals.runs += r.runs || 0;
    totals.wickets += r.wickets || 0;
    if ((r.runs || 0) > totals.best || ((r.runs || 0) === totals.best && line.notOut)) {
      totals.best = r.runs || 0;
      totals.bestNotOut = !!line.notOut;
    }
  }

  const teamRows = await env.DB.prepare(
    `SELECT DISTINCT pp.scorer_id, pp.team_id, pp.team FROM claims c
     JOIN player_phones pp ON pp.scorer_id = c.scorer_id AND pp.player_id = c.player_id
     WHERE c.user_id = ? AND c.status = 'ok' AND pp.team_id != '' LIMIT 10`,
  ).bind(user.id).all();
  const teams = [];
  for (const t of teamRows.results || []) teams.push(await teamInfo(env, t.scorer_id, t.team_id, t.team));
  return { matches, teams, totals };
}

async function teamInfo(env, scorerId, teamId, name) {
  const rows = await env.DB.prepare(
    `SELECT ${MATCH_COLS} FROM matches m WHERE m.scorer_id = ? AND (m.team_a = ? OR m.team_b = ?)
     ORDER BY COALESCE(m.scheduled, m.updated) DESC LIMIT 60`,
  ).bind(scorerId, teamId, teamId).all();
  const list = (rows.results || []).map(matchItem);
  const results = list.filter((m) => m.status === 'result');
  const won = results.filter((m) => m.winner === teamId).length;
  const tied = results.filter((m) => m.winner === 'tie').length;
  const form = results.slice(0, 5).map((m) => (m.winner === teamId ? 'W' : m.winner === 'tie' ? 'T' : m.winner ? 'L' : '-'));
  const now = Date.now();
  const next = list
    .filter((m) => m.status === 'upcoming' && (m.scheduled ?? 0) >= now - 3 * HOUR)
    .sort((a, b) => (a.scheduled ?? 0) - (b.scheduled ?? 0))[0] || null;
  const rating = await env.DB.prepare(
    'SELECT COUNT(*) AS n, AVG((fair + behaviour + ontime) / 3.0) AS avg FROM ratings WHERE scorer_id = ? AND team_id = ?',
  ).bind(scorerId, teamId).first();
  return {
    scorerId,
    id: teamId,
    name: name || '',
    played: results.length,
    won,
    lost: results.length - won - tied,
    form,
    next,
    rating: rating && rating.n ? Math.round(rating.avg * 10) / 10 : null,
    ratings: rating ? rating.n : 0,
    matches: list.slice(0, 30),
  };
}

async function oneUser(env, id) {
  return env.DB.prepare('SELECT id, email, name FROM users WHERE id = ?').bind(id).first();
}

/** Removes a user and everything they made (Settings → Delete my account). */
export async function deleteUserEverywhere(env, userId) {
  await deleteUserTeamData(env, userId);
  if (env.PHOTOS) {
    const ph = await env.DB.prepare('SELECT id, ground_id FROM ground_photos WHERE user_id = ?').bind(userId).all();
    const keys = (ph.results || []).map((x) => photoKey(x.ground_id, x.id));
    for (let i = 0; i < keys.length; i += 500) await env.PHOTOS.delete(keys.slice(i, i + 500));
  }
  await env.DB.batch([
    env.DB.prepare('DELETE FROM sessions WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM claims WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM post_joins WHERE user_id = ? OR post_id IN (SELECT id FROM posts WHERE user_id = ?)').bind(userId, userId),
    env.DB.prepare('DELETE FROM poll_votes WHERE user_id = ? OR post_id IN (SELECT id FROM posts WHERE user_id = ?)').bind(userId, userId),
    env.DB.prepare('DELETE FROM posts WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM reactions WHERE user_id = ? OR comment_id IN (SELECT id FROM comments WHERE user_id = ?)').bind(userId, userId),
    env.DB.prepare("DELETE FROM comments WHERE parent_id IN (SELECT id FROM comments WHERE user_id = ?)").bind(userId),
    env.DB.prepare('DELETE FROM comments WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM ratings WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM reports WHERE user_id = ?').bind(userId),
    env.DB.prepare("UPDATE grounds SET user_id = '' WHERE user_id = ?").bind(userId),
    env.DB.prepare('DELETE FROM ground_reviews WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM ground_photos WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM bookings WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM users WHERE id = ?').bind(userId),
  ]);
}

/** Optional login: the user row when a valid "Bearer U..." header is sent, else null. */
async function maybeUser(request, env) {
  if (!/^Bearer U/.test(request.headers.get('authorization') || '')) return null;
  try {
    return await userAuth(request, env);
  } catch {
    return null;
  }
}

// ---------- Community ----------

const KINDS = ['players', 'opponent', 'poll', 'tournament', 'general'];

async function postView(env, r, me) {
  const extra = parse(r.extra, {});
  const author = await oneUser(env, r.user_id);
  const joins = await env.DB.prepare('SELECT COUNT(*) AS n FROM post_joins WHERE post_id = ?').bind(r.id).first();
  const joined = me ? await env.DB.prepare('SELECT paid FROM post_joins WHERE post_id = ? AND user_id = ?').bind(r.id, me.id).first() : null;
  const out = {
    id: r.id,
    kind: r.kind,
    body: r.body,
    place: r.place,
    created: r.created,
    author: { name: author?.name || 'Player' },
    mine: !!me && me.id === r.user_id,
    joins: joins?.n || 0,
    joined: !!joined,
    paid: !!joined?.paid,
    hasContact: !!r.contact,
    extra,
  };
  // The WhatsApp number is only for people who joined (and the author).
  if (r.contact && (out.joined || out.mine)) out.contact = r.contact;
  if (r.kind === 'poll') {
    const votes = await env.DB.prepare('SELECT option, COUNT(*) AS n FROM poll_votes WHERE post_id = ? GROUP BY option').bind(r.id).all();
    const counts = (extra.options || []).map(() => 0);
    for (const v of votes.results || []) if (v.option < counts.length) counts[v.option] = v.n;
    out.votes = counts;
    const mine = me ? await env.DB.prepare('SELECT option FROM poll_votes WHERE post_id = ? AND user_id = ?').bind(r.id, me.id).first() : null;
    out.myVote = mine ? mine.option : null;
  }
  return out;
}

// ---------- Ratings & comments ----------

async function commentView(env, r, me) {
  const author = await oneUser(env, r.user_id);
  const rx = await env.DB.prepare('SELECT emoji, COUNT(*) AS n FROM reactions WHERE comment_id = ? GROUP BY emoji ORDER BY n DESC').bind(r.id).all();
  const mine = me ? await env.DB.prepare('SELECT emoji FROM reactions WHERE comment_id = ? AND user_id = ?').bind(r.id, me.id).first() : null;
  const replies = await env.DB.prepare('SELECT COUNT(*) AS n FROM comments WHERE parent_id = ? AND hidden = 0').bind(r.id).first();
  return {
    id: r.id,
    parentId: r.parent_id || null,
    author: { name: author?.name || 'Player', team: r.author_team },
    isTeam: !!r.is_team,
    stars: r.stars || 0,
    body: r.body,
    created: r.created,
    mine: !!me && me.id === r.user_id,
    reactions: (rx.results || []).map((x) => ({ emoji: x.emoji, n: x.n })),
    myReaction: mine ? mine.emoji : null,
    replies: replies?.n || 0,
  };
}

const EMOJIS = ['👍', '❤️', '😂', '🔥', '👏', '😮'];
const TAGS = ['sportsmen', 'tough', 'late', 'again'];

/** The routes; returns null when the path is not one of these. */
export async function socialRoutes(p, method, url, request, env) {
  let m;

  // ----- Feed: every match on GullyScore -----
  if (p === '/v1/feed' && method === 'GET') {
    const kind = url.searchParams.get('kind') || 'live';
    const before = Number(url.searchParams.get('before') || '0');
    const now = Date.now();
    let rows;
    if (kind === 'live') {
      rows = await env.DB.prepare(`SELECT ${MATCH_COLS} FROM matches m WHERE m.status = 'live' AND m.updated > ? ORDER BY m.updated DESC LIMIT 50`)
        .bind(now - LIVE_FOR).all();
    } else if (kind === 'upcoming') {
      rows = await env.DB.prepare(
        `SELECT ${MATCH_COLS} FROM matches m WHERE m.status = 'upcoming' AND m.scheduled >= ? ORDER BY m.scheduled ASC LIMIT 50`,
      ).bind(now - 3 * HOUR).all();
    } else if (kind === 'results') {
      rows = await env.DB.prepare(
        `SELECT ${MATCH_COLS} FROM matches m WHERE m.status = 'result' AND m.updated < ? ORDER BY m.updated DESC LIMIT 30`,
      ).bind(before > 0 ? before : now + HOUR).all();
    } else {
      throw new HttpError(400, 'bad kind');
    }
    const live = await env.DB.prepare("SELECT COUNT(*) AS n FROM matches WHERE status = 'live' AND updated > ?").bind(now - LIVE_FOR).first();
    const up = await env.DB.prepare("SELECT COUNT(*) AS n FROM matches WHERE status = 'upcoming' AND scheduled >= ?").bind(now - 3 * HOUR).first();
    return json({ matches: (rows.results || []).map(matchItem), counts: { live: live?.n || 0, upcoming: up?.n || 0 } });
  }

  // ----- One team: its matches, form and rating -----
  if ((m = /^\/v1\/teams\/([^/]+)\/([^/]+)$/.exec(p)) && method === 'GET') {
    if (!ID_RE.test(m[1]) || !ID_RE.test(m[2])) throw new HttpError(400, 'bad id');
    const row = await env.DB.prepare(
      'SELECT CASE WHEN team_a = ? THEN team_a_name ELSE team_b_name END AS name FROM matches WHERE scorer_id = ? AND (team_a = ? OR team_b = ?) ORDER BY updated DESC LIMIT 1',
    ).bind(m[2], m[1], m[2], m[2]).first();
    return json(await teamInfo(env, m[1], m[2], row?.name || ''));
  }

  // ----- Leaderboard -----
  if (p === '/v1/leaderboard' && method === 'GET') {
    const kind = url.searchParams.get('kind') === 'wickets' ? 'wickets' : 'runs';
    const days = clamp(url.searchParams.get('days'), 0, 3650);
    const since = days ? Date.now() - days * 24 * HOUR : 0;
    const rows = await env.DB.prepare(
      `SELECT m.scorer_id, mp.player_id, MAX(mp.name) AS name, SUM(mp.runs) AS runs, SUM(mp.wickets) AS wickets, COUNT(*) AS matches,
       MAX(mp.runs) AS best FROM match_players mp JOIN matches m ON m.id = mp.match_id
       WHERE m.status != 'upcoming' AND m.updated >= ? AND mp.name != ''
       GROUP BY m.scorer_id, mp.player_id HAVING ${kind} > 0 ORDER BY ${kind} DESC, matches ASC LIMIT 50`,
    ).bind(since).all();
    const out = [];
    for (const r of rows.results || []) {
      const t = await env.DB.prepare(
        `SELECT mp.team, CASE WHEN m.team_a = mp.team THEN m.team_a_name ELSE m.team_b_name END AS team_name FROM match_players mp
         JOIN matches m ON m.id = mp.match_id WHERE m.scorer_id = ? AND mp.player_id = ? ORDER BY m.updated DESC LIMIT 1`,
      ).bind(r.scorer_id, r.player_id).first();
      out.push({ name: r.name, team: t?.team_name || '', runs: r.runs, wickets: r.wickets, matches: r.matches, best: r.best });
    }
    return json({ kind, days, players: out });
  }

  // ----- Delete my account -----
  if (p === '/v1/me/account' && method === 'DELETE') {
    const user = await userAuth(request, env);
    await deleteUserEverywhere(env, user.id);
    return json({ ok: true });
  }

  // ----- Community posts -----
  if (p === '/v1/posts' && method === 'GET') {
    const me = await maybeUser(request, env);
    const kind = url.searchParams.get('kind') || '';
    const before = Number(url.searchParams.get('before') || '0') || Date.now() + HOUR;
    const rows = kind && KINDS.includes(kind)
      ? await env.DB.prepare('SELECT * FROM posts WHERE hidden = 0 AND kind = ? AND created < ? ORDER BY created DESC LIMIT 30').bind(kind, before).all()
      : await env.DB.prepare('SELECT * FROM posts WHERE hidden = 0 AND created < ? ORDER BY created DESC LIMIT 30').bind(before).all();
    const posts = [];
    for (const r of rows.results || []) posts.push(await postView(env, r, me));
    return json({ posts });
  }

  if (p === '/v1/posts' && method === 'POST') {
    const user = await userAuth(request, env);
    const b = await readJson(request);
    const kind = KINDS.includes(b?.kind) ? b.kind : null;
    const body = str(b?.body, 600);
    if (!kind || !body) throw new HttpError(400, 'missing');
    const recent = await env.DB.prepare('SELECT COUNT(*) AS n FROM posts WHERE user_id = ? AND created > ?').bind(user.id, Date.now() - 24 * HOUR).first();
    if ((recent?.n || 0) >= 10) throw new HttpError(429, 'too many posts today');
    const extra = {};
    if (kind === 'poll') {
      extra.options = (Array.isArray(b.options) ? b.options : []).map((o) => str(o, 80)).filter(Boolean).slice(0, 6);
      if (extra.options.length < 2) throw new HttpError(400, 'two options needed');
    }
    if (kind === 'tournament') {
      extra.fee = clamp(b.fee, 0, 1000000);
      extra.upi = str(b.upi, 80);
      extra.teams = clamp(b.teams, 0, 256);
      extra.lastDate = str(b.lastDate, 20);
      extra.prize = str(b.prize, 120);
    }
    if (kind === 'players') extra.need = clamp(b.need, 0, 11);
    if (b.when) extra.when = str(b.when, 60);
    const contact = String(b.contact ?? '').replace(/[^\d+]/g, '').slice(0, 15);
    const id = randomString(14, TOKEN_ALPHABET);
    await env.DB.prepare('INSERT INTO posts (id, user_id, kind, body, place, extra, contact, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
      .bind(id, user.id, kind, body, str(b.place, 80), JSON.stringify(extra), contact, Date.now())
      .run();
    const row = await env.DB.prepare('SELECT * FROM posts WHERE id = ?').bind(id).first();
    return json(await postView(env, row, user));
  }

  if ((m = /^\/v1\/posts\/([A-Za-z0-9]+)$/.exec(p)) && method === 'DELETE') {
    const user = await userAuth(request, env);
    const row = await env.DB.prepare('SELECT user_id FROM posts WHERE id = ?').bind(m[1]).first();
    if (!row) return json({ ok: true });
    if (row.user_id !== user.id) throw new HttpError(403, 'not your post');
    await env.DB.batch([
      env.DB.prepare('DELETE FROM post_joins WHERE post_id = ?').bind(m[1]),
      env.DB.prepare('DELETE FROM poll_votes WHERE post_id = ?').bind(m[1]),
      env.DB.prepare('DELETE FROM posts WHERE id = ?').bind(m[1]),
    ]);
    return json({ ok: true });
  }

  // I'm in / Register team (toggle with {join:false})
  if ((m = /^\/v1\/posts\/([A-Za-z0-9]+)\/join$/.exec(p)) && method === 'POST') {
    const user = await userAuth(request, env);
    const b = await readJson(request);
    const row = await env.DB.prepare('SELECT * FROM posts WHERE id = ? AND hidden = 0').bind(m[1]).first();
    if (!row) throw new HttpError(404, 'no such post');
    if (b?.join === false) {
      await env.DB.prepare('DELETE FROM post_joins WHERE post_id = ? AND user_id = ?').bind(m[1], user.id).run();
    } else {
      const r = await env.DB.prepare('INSERT OR IGNORE INTO post_joins (post_id, user_id, note, created) VALUES (?, ?, ?, ?)')
        .bind(m[1], user.id, str(b?.note, 80), Date.now())
        .run();
      if (r.meta?.changes && row.user_id !== user.id) {
        await push(env, [topic('u', row.user_id)], `🙌 ${user.name || 'Someone'} joined your post`, str(b?.note, 80) || row.body.slice(0, 80), { post: row.id });
      }
    }
    return json(await postView(env, row, user));
  }

  // The author sees who joined, and ticks "paid" for tournaments.
  if ((m = /^\/v1\/posts\/([A-Za-z0-9]+)\/joins$/.exec(p)) && method === 'GET') {
    const user = await userAuth(request, env);
    const row = await env.DB.prepare('SELECT user_id FROM posts WHERE id = ?').bind(m[1]).first();
    if (!row || row.user_id !== user.id) throw new HttpError(403, 'not your post');
    const rows = await env.DB.prepare(
      'SELECT j.user_id, j.note, j.paid, u.name, u.email FROM post_joins j JOIN users u ON u.id = j.user_id WHERE j.post_id = ? ORDER BY j.created',
    ).bind(m[1]).all();
    return json({ joins: (rows.results || []).map((r) => ({ userId: r.user_id, name: r.name, email: r.email, note: r.note, paid: !!r.paid })) });
  }

  if ((m = /^\/v1\/posts\/([A-Za-z0-9]+)\/paid$/.exec(p)) && method === 'POST') {
    const user = await userAuth(request, env);
    const b = await readJson(request);
    const row = await env.DB.prepare('SELECT user_id FROM posts WHERE id = ?').bind(m[1]).first();
    if (!row || row.user_id !== user.id) throw new HttpError(403, 'not your post');
    await env.DB.prepare('UPDATE post_joins SET paid = ? WHERE post_id = ? AND user_id = ?').bind(b?.paid ? 1 : 0, m[1], str(b?.userId, 80)).run();
    return json({ ok: true });
  }

  if ((m = /^\/v1\/posts\/([A-Za-z0-9]+)\/vote$/.exec(p)) && method === 'POST') {
    const user = await userAuth(request, env);
    const b = await readJson(request);
    const row = await env.DB.prepare("SELECT * FROM posts WHERE id = ? AND kind = 'poll' AND hidden = 0").bind(m[1]).first();
    if (!row) throw new HttpError(404, 'no such poll');
    const n = (parse(row.extra, {}).options || []).length;
    const option = clamp(b?.option, 0, 99);
    if (option >= n) throw new HttpError(400, 'bad option');
    await env.DB.prepare('INSERT INTO poll_votes (post_id, user_id, option) VALUES (?, ?, ?) ON CONFLICT(post_id, user_id) DO UPDATE SET option = excluded.option')
      .bind(m[1], user.id, option)
      .run();
    return json(await postView(env, row, user));
  }

  // ----- Ratings -----
  // Which matches can I rate? (finished, I played, not rated yet)
  if ((m = /^\/v1\/matches\/([^/]+)\/rating$/.exec(p)) && method === 'GET') {
    const user = await userAuth(request, env);
    return json(await ratingTarget(env, user, m[1]));
  }

  if ((m = /^\/v1\/matches\/([^/]+)\/rating$/.exec(p)) && method === 'POST') {
    const user = await userAuth(request, env);
    const t = await ratingTarget(env, user, m[1]);
    if (!t.canRate) throw new HttpError(403, t.reason || 'cannot rate');
    const b = await readJson(request);
    const fair = clamp(b?.fair, 1, 5);
    const behaviour = clamp(b?.behaviour, 1, 5);
    const ontime = clamp(b?.ontime, 1, 5);
    const tags = (Array.isArray(b?.tags) ? b.tags : []).filter((x) => TAGS.includes(x)).slice(0, 4);
    const now = Date.now();
    const stmts = [
      env.DB.prepare('INSERT INTO ratings (match_id, user_id, scorer_id, team_id, fair, behaviour, ontime, tags, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
        .bind(m[1], user.id, t.scorerId, t.team.id, fair, behaviour, ontime, JSON.stringify(tags), now),
    ];
    const text = str(b?.comment, 600);
    if (text) {
      stmts.push(
        env.DB.prepare(
          'INSERT INTO comments (id, scorer_id, team_id, match_id, parent_id, user_id, author_team, is_team, stars, body, created) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)',
        ).bind(randomString(14, TOKEN_ALPHABET), t.scorerId, t.team.id, m[1], '', user.id, t.myTeam.name, Math.round(((fair + behaviour + ontime) / 3) * 10) / 10, text, now),
      );
    }
    await env.DB.batch(stmts);
    return json({ ok: true });
  }

  // Team ratings page: averages, tags and comments.
  if ((m = /^\/v1\/teams\/([^/]+)\/([^/]+)\/ratings$/.exec(p)) && method === 'GET') {
    const me = await maybeUser(request, env);
    const [, scorerId, teamId] = m;
    const avg = await env.DB.prepare(
      'SELECT COUNT(*) AS n, AVG(fair) AS fair, AVG(behaviour) AS behaviour, AVG(ontime) AS ontime FROM ratings WHERE scorer_id = ? AND team_id = ?',
    ).bind(scorerId, teamId).first();
    const tagCounts = Object.fromEntries(TAGS.map((t) => [t, 0]));
    const tr = await env.DB.prepare('SELECT tags FROM ratings WHERE scorer_id = ? AND team_id = ?').bind(scorerId, teamId).all();
    for (const r of tr.results || []) for (const t of parse(r.tags, [])) if (t in tagCounts) tagCounts[t]++;
    const sort = url.searchParams.get('sort') === 'top' ? 'top' : 'new';
    const rows = await env.DB.prepare(
      `SELECT c.*, (SELECT COUNT(*) FROM reactions r WHERE r.comment_id = c.id) AS rx FROM comments c
       WHERE c.scorer_id = ? AND c.team_id = ? AND c.parent_id = '' AND c.hidden = 0
       ORDER BY ${sort === 'top' ? 'rx DESC, c.created DESC' : 'c.created DESC'} LIMIT 50`,
    ).bind(scorerId, teamId).all();
    const comments = [];
    for (const r of rows.results || []) {
      const c = await commentView(env, r, me);
      const reps = await env.DB.prepare("SELECT * FROM comments WHERE parent_id = ? AND hidden = 0 ORDER BY created ASC LIMIT 2").bind(r.id).all();
      c.firstReplies = [];
      for (const x of reps.results || []) c.firstReplies.push(await commentView(env, x, me));
      comments.push(c);
    }
    const r1 = (v) => (v == null ? null : Math.round(v * 10) / 10);
    return json({
      count: avg?.n || 0,
      overall: avg?.n ? r1((avg.fair + avg.behaviour + avg.ontime) / 3) : null,
      fair: r1(avg?.fair),
      behaviour: r1(avg?.behaviour),
      ontime: r1(avg?.ontime),
      tags: tagCounts,
      comments,
    });
  }

  // Replies to one comment.
  if ((m = /^\/v1\/comments\/([A-Za-z0-9]+)\/replies$/.exec(p)) && method === 'GET') {
    const me = await maybeUser(request, env);
    const rows = await env.DB.prepare('SELECT * FROM comments WHERE parent_id = ? AND hidden = 0 ORDER BY created ASC LIMIT 200').bind(m[1]).all();
    const out = [];
    for (const r of rows.results || []) out.push(await commentView(env, r, me));
    return json({ replies: out });
  }

  if ((m = /^\/v1\/comments\/([A-Za-z0-9]+)\/replies$/.exec(p)) && method === 'POST') {
    const user = await userAuth(request, env);
    const b = await readJson(request);
    const text = str(b?.body, 600);
    if (!text) throw new HttpError(400, 'empty');
    const parent = await env.DB.prepare("SELECT * FROM comments WHERE id = ? AND hidden = 0").bind(m[1]).first();
    if (!parent) throw new HttpError(404, 'no such comment');
    const root = parent.parent_id ? await env.DB.prepare('SELECT * FROM comments WHERE id = ?').bind(parent.parent_id).first() : parent;
    // Is the writer a player of the rated team?
    const team = await env.DB.prepare(
      `SELECT pp.team FROM claims c JOIN player_phones pp ON pp.scorer_id = c.scorer_id AND pp.player_id = c.player_id
       WHERE c.user_id = ? AND c.status = 'ok' AND pp.scorer_id = ? AND pp.team_id = ? LIMIT 1`,
    ).bind(user.id, root.scorer_id, root.team_id).first();
    const id = randomString(14, TOKEN_ALPHABET);
    await env.DB.prepare(
      'INSERT INTO comments (id, scorer_id, team_id, match_id, parent_id, user_id, author_team, is_team, body, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    ).bind(id, root.scorer_id, root.team_id, root.match_id, root.id, user.id, team?.team || '', team ? 1 : 0, text, Date.now()).run();
    const row = await env.DB.prepare('SELECT * FROM comments WHERE id = ?').bind(id).first();
    if (parent.user_id !== user.id) {
      await push(env, [topic('u', parent.user_id)], `💬 ${user.name || 'Someone'} replied to you`, text.slice(0, 120), { team: root.team_id, scorer: root.scorer_id });
    }
    return json(await commentView(env, row, user));
  }

  if ((m = /^\/v1\/comments\/([A-Za-z0-9]+)$/.exec(p)) && method === 'DELETE') {
    const user = await userAuth(request, env);
    const row = await env.DB.prepare('SELECT user_id FROM comments WHERE id = ?').bind(m[1]).first();
    if (!row) return json({ ok: true });
    if (row.user_id !== user.id) throw new HttpError(403, 'not yours');
    await env.DB.batch([
      env.DB.prepare('DELETE FROM reactions WHERE comment_id = ? OR comment_id IN (SELECT id FROM comments WHERE parent_id = ?)').bind(m[1], m[1]),
      env.DB.prepare('DELETE FROM comments WHERE parent_id = ?').bind(m[1]),
      env.DB.prepare('DELETE FROM comments WHERE id = ?').bind(m[1]),
    ]);
    return json({ ok: true });
  }

  // React (same emoji again removes it).
  if ((m = /^\/v1\/comments\/([A-Za-z0-9]+)\/react$/.exec(p)) && method === 'POST') {
    const user = await userAuth(request, env);
    const b = await readJson(request);
    const row = await env.DB.prepare('SELECT * FROM comments WHERE id = ? AND hidden = 0').bind(m[1]).first();
    if (!row) throw new HttpError(404, 'no such comment');
    const old = await env.DB.prepare('SELECT emoji FROM reactions WHERE comment_id = ? AND user_id = ?').bind(m[1], user.id).first();
    const emoji = EMOJIS.includes(b?.emoji) ? b.emoji : null;
    if (!emoji || (old && old.emoji === emoji)) {
      await env.DB.prepare('DELETE FROM reactions WHERE comment_id = ? AND user_id = ?').bind(m[1], user.id).run();
    } else {
      await env.DB.prepare('INSERT INTO reactions (comment_id, user_id, emoji) VALUES (?, ?, ?) ON CONFLICT(comment_id, user_id) DO UPDATE SET emoji = excluded.emoji')
        .bind(m[1], user.id, emoji)
        .run();
      if (!old && row.user_id !== user.id) {
        await push(env, [topic('u', row.user_id)], `${emoji} ${user.name || 'Someone'} reacted to your comment`, row.body.slice(0, 120), { team: row.team_id, scorer: row.scorer_id });
      }
    }
    return json(await commentView(env, row, user));
  }

  // ----- Reports -----
  if (p === '/v1/reports' && method === 'POST') {
    const user = await userAuth(request, env);
    const b = await readJson(request);
    const kind = b?.kind === 'post' ? 'post' : b?.kind === 'comment' ? 'comment' : null;
    const target = str(b?.id, 40);
    if (!kind || !target) throw new HttpError(400, 'missing');
    await env.DB.prepare('INSERT OR IGNORE INTO reports (kind, target_id, user_id, reason, created) VALUES (?, ?, ?, ?, ?)')
      .bind(kind, target, user.id, str(b?.reason, 200), Date.now())
      .run();
    const n = await env.DB.prepare('SELECT COUNT(*) AS n FROM reports WHERE kind = ? AND target_id = ?').bind(kind, target).first();
    if ((n?.n || 0) >= HIDE_AFTER_REPORTS) {
      await env.DB.prepare(`UPDATE ${kind === 'post' ? 'posts' : 'comments'} SET hidden = 1 WHERE id = ?`).bind(target).run();
    }
    return json({ ok: true });
  }

  return null;
}

/** Who this user can rate in a match: the other team, once, after the match. */
async function ratingTarget(env, user, matchId) {
  const match = await env.DB.prepare('SELECT * FROM matches WHERE id = ?').bind(matchId).first();
  if (!match) throw new HttpError(404, 'no such match');
  const mine = await env.DB.prepare(
    `SELECT mp.team FROM claims c JOIN match_players mp ON mp.player_id = c.player_id AND mp.match_id = ?
     WHERE c.user_id = ? AND c.status = 'ok' AND c.scorer_id = ? LIMIT 1`,
  ).bind(matchId, user.id, match.scorer_id).first();
  const base = { canRate: false, scorerId: match.scorer_id };
  if (!mine || !mine.team) return { ...base, reason: 'not your match' };
  if (match.status !== 'result') return { ...base, reason: 'not finished' };
  const other = mine.team === match.team_a ? { id: match.team_b, name: match.team_b_name } : { id: match.team_a, name: match.team_a_name };
  const myTeam = mine.team === match.team_a ? { id: match.team_a, name: match.team_a_name } : { id: match.team_b, name: match.team_b_name };
  if (!other.id) return { ...base, reason: 'no team' };
  const done = await env.DB.prepare('SELECT 1 FROM ratings WHERE match_id = ? AND user_id = ? AND team_id = ?').bind(matchId, user.id, other.id).first();
  if (done) return { ...base, team: other, myTeam, rated: true, reason: 'already rated' };
  return { canRate: true, scorerId: match.scorer_id, team: other, myTeam, rated: false };
}
