// GullyScore online service (Cloudflare Worker + D1).
//
// Phones that score upload their matches here. Anyone with a match link can
// watch it live, in the app or in a browser. Players log in with Google,
// type their mobile number, and (after the scorer says yes once) see all
// their matches. Mobile numbers are kept only as keyed hashes.
// Photos never come here: they stay on the phones.

const MAX_BODY = 600 * 1024; // a long match is ~50 KB; this leaves room
const ID_RE = /^[A-Za-z0-9_\-]{1,80}$/;
const TOKEN_ALPHABET = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status);
      return json({ error: 'server error' }, 500);
    }
  },
};

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': '*',
      'cache-control': 'no-store',
      ...extra,
    },
  });
}

async function readJson(request) {
  const len = Number(request.headers.get('content-length') || '0');
  if (len > MAX_BODY) throw new HttpError(413, 'too large');
  const text = await request.text();
  if (text.length > MAX_BODY) throw new HttpError(413, 'too large');
  try {
    return JSON.parse(text);
  } catch {
    throw new HttpError(400, 'bad json');
  }
}

function randomString(n, alphabet) {
  const bytes = new Uint8Array(n);
  crypto.getRandomValues(bytes);
  let s = '';
  for (const b of bytes) s += alphabet[b % alphabet.length];
  return s;
}

async function sha256(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Checks "Authorization: Bearer <scorerId>.<token>" and returns the scorer id. */
async function auth(request, env) {
  const h = request.headers.get('authorization') || '';
  const m = /^Bearer ([A-Za-z0-9_\-]+)\.([A-Za-z0-9_\-]+)$/.exec(h);
  if (!m) throw new HttpError(401, 'not signed in');
  const row = await env.DB.prepare('SELECT token_hash FROM scorers WHERE id = ?').bind(m[1]).first();
  if (!row || row.token_hash !== (await sha256(m[2]))) throw new HttpError(401, 'not signed in');
  return m[1];
}

/** Checks "Authorization: Bearer U<token>" (a logged-in player) and returns the user row. */
async function userAuth(request, env) {
  const h = request.headers.get('authorization') || '';
  const m = /^Bearer U([A-Za-z0-9]+)$/.exec(h);
  if (!m) throw new HttpError(401, 'not logged in');
  const row = await env.DB.prepare('SELECT u.id, u.email, u.name, u.phone_hash FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?')
    .bind(await sha256(m[1]))
    .first();
  if (!row) throw new HttpError(401, 'not logged in');
  return row;
}

/** Scorer id from a "<id>.<token>" string, or null when it does not check out. */
async function scorerFrom(text, env) {
  const m = /^([A-Za-z0-9_\-]+)\.([A-Za-z0-9_\-]+)$/.exec(typeof text === 'string' ? text : '');
  if (!m) return null;
  const row = await env.DB.prepare('SELECT token_hash FROM scorers WHERE id = ?').bind(m[1]).first();
  return row && row.token_hash === (await sha256(m[2])) ? m[1] : null;
}

/** The random key used to hash mobile numbers (made once, kept in the database). */
async function phoneKey(env) {
  let row = await env.DB.prepare("SELECT v FROM config WHERE k = 'phone_key'").first();
  if (!row) {
    await env.DB.prepare("INSERT OR IGNORE INTO config (k, v) VALUES ('phone_key', ?)").bind(randomString(48, TOKEN_ALPHABET)).run();
    row = await env.DB.prepare("SELECT v FROM config WHERE k = 'phone_key'").first();
  }
  return row.v;
}

/** Last 10 digits of a mobile number, or null if it is not one. */
function cleanPhone(raw) {
  const d = String(raw ?? '').replace(/\D/g, '');
  return d.length >= 10 && d.length <= 15 ? d.slice(-10) : null;
}

async function phoneHash(key, digits) {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(digits));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Asks Google whether a sign-in token is real and meant for this app. */
async function verifyGoogle(idToken, env) {
  if (env.VERIFY_GOOGLE) {
    // tests
    try {
      return await env.VERIFY_GOOGLE(idToken);
    } catch {
      throw new HttpError(401, 'google login failed');
    }
  }
  const clientId = String(env.GOOGLE_CLIENT_ID || '').trim();
  if (!clientId) throw new HttpError(503, 'login not set up');
  let r;
  try {
    r = await fetch('https://oauth2.googleapis.com/tokeninfo?id_token=' + encodeURIComponent(idToken));
  } catch {
    throw new HttpError(502, 'google did not answer');
  }
  if (!r.ok) throw new HttpError(401, 'google login failed');
  const t = await r.json();
  const okIssuer = t.iss === 'accounts.google.com' || t.iss === 'https://accounts.google.com';
  const verified = t.email_verified === true || t.email_verified === 'true';
  if (t.aud !== clientId || !okIssuer || !verified || Number(t.exp) * 1000 < Date.now() || !t.sub) {
    throw new HttpError(401, 'google login failed');
  }
  return { sub: String(t.sub), email: String(t.email || ''), name: String(t.name || '') };
}

/** Everything a logged-in player sees: their profiles and their matches. */
async function meInfo(user, env) {
  const profiles = await env.DB.prepare(
    `SELECT c.status, pp.name, pp.team FROM claims c
     LEFT JOIN player_phones pp ON pp.scorer_id = c.scorer_id AND pp.player_id = c.player_id
     WHERE c.user_id = ? ORDER BY c.created`,
  ).bind(user.id).all();
  const matches = await env.DB.prepare(
    `SELECT DISTINCT m.id, m.updated, m.finished, m.title, m.summary FROM claims c
     JOIN match_players mp ON mp.player_id = c.player_id
     JOIN matches m ON m.id = mp.match_id AND m.scorer_id = c.scorer_id
     WHERE c.user_id = ? AND c.status = 'ok' ORDER BY m.updated DESC LIMIT 100`,
  ).bind(user.id).all();
  return {
    email: user.email,
    name: user.name,
    hasPhone: !!user.phone_hash,
    profiles: (profiles.results || []).map((r) => ({ status: r.status, name: r.name || '', team: r.team || '' })),
    matches: (matches.results || []).map((r) => ({ id: r.id, updated: r.updated, finished: !!r.finished, title: r.title, summary: JSON.parse(r.summary) })),
  };
}

async function route(request, env) {
  const url = new URL(request.url);
  const p = url.pathname.replace(/\/+$/, '') || '/';
  const method = request.method;

  if (method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'GET, PUT, POST, DELETE',
        'access-control-allow-headers': 'authorization, content-type',
      },
    });
  }

  if (p === '/' || p === '/v1/health') return json({ ok: true, service: 'gullyscore', login: !!String(env.GOOGLE_CLIENT_ID || '').trim() });

  // A phone asks for its own identity once.
  if (p === '/v1/register' && method === 'POST') {
    const id = randomString(16, 'abcdefghijklmnopqrstuvwxyz0123456789');
    const token = randomString(32, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789');
    await env.DB.prepare('INSERT INTO scorers (id, token_hash, created) VALUES (?, ?, ?)').bind(id, await sha256(token), Date.now()).run();
    return json({ scorerId: id, token });
  }

  let m;

  // Upload or update a match (only the phone that first uploaded it may change it).
  if ((m = /^\/v1\/matches\/([^/]+)$/.exec(p)) && method === 'PUT') {
    const matchId = m[1];
    if (!ID_RE.test(matchId)) throw new HttpError(400, 'bad id');
    const scorer = await auth(request, env);
    const body = await readJson(request);
    if (typeof body !== 'object' || !body || typeof body.data !== 'object' || typeof body.summary !== 'object') {
      throw new HttpError(400, 'missing data');
    }
    const existing = await env.DB.prepare('SELECT scorer_id FROM matches WHERE id = ?').bind(matchId).first();
    if (existing && existing.scorer_id !== scorer) throw new HttpError(403, 'not your match');
    const players = Array.isArray(body.players) ? body.players.filter((x) => typeof x === 'string' && ID_RE.test(x)).slice(0, 80) : [];
    const now = Date.now();
    const title = typeof body.title === 'string' ? body.title.slice(0, 120) : '';
    const stmts = [
      env.DB.prepare(
        `INSERT INTO matches (id, scorer_id, updated, finished, title, summary, data) VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET updated = excluded.updated, finished = excluded.finished, title = excluded.title,
         summary = excluded.summary, data = excluded.data`,
      ).bind(matchId, scorer, now, body.finished ? 1 : 0, title, JSON.stringify(body.summary), JSON.stringify(body.data)),
      env.DB.prepare('DELETE FROM match_players WHERE match_id = ?').bind(matchId),
      ...players.map((pid) => env.DB.prepare('INSERT OR IGNORE INTO match_players (match_id, player_id) VALUES (?, ?)').bind(matchId, pid)),
    ];
    await env.DB.batch(stmts);
    return json({ ok: true, updated: now });
  }

  if ((m = /^\/v1\/matches\/([^/]+)$/.exec(p)) && method === 'DELETE') {
    const scorer = await auth(request, env);
    const existing = await env.DB.prepare('SELECT scorer_id FROM matches WHERE id = ?').bind(m[1]).first();
    if (!existing) return json({ ok: true });
    if (existing.scorer_id !== scorer) throw new HttpError(403, 'not your match');
    await env.DB.batch([
      env.DB.prepare('DELETE FROM matches WHERE id = ?').bind(m[1]),
      env.DB.prepare('DELETE FROM match_players WHERE match_id = ?').bind(m[1]),
    ]);
    return json({ ok: true });
  }

  // Watch a match. ?since=<updated> answers {unchanged:true} if nothing is new.
  if ((m = /^\/v1\/matches\/([^/]+)$/.exec(p)) && method === 'GET') {
    const row = await env.DB.prepare('SELECT updated, finished, summary, data FROM matches WHERE id = ?').bind(m[1]).first();
    if (!row) throw new HttpError(404, 'no such match');
    const since = Number(url.searchParams.get('since') || '0');
    if (since && since >= row.updated) return json({ unchanged: true, updated: row.updated });
    return json({ updated: row.updated, finished: !!row.finished, summary: JSON.parse(row.summary), data: JSON.parse(row.data) });
  }

  // All matches a player played in (newest first).
  if ((m = /^\/v1\/players\/([^/]+)\/matches$/.exec(p)) && method === 'GET') {
    const rows = await env.DB.prepare(
      `SELECT m.id, m.updated, m.finished, m.title, m.summary FROM match_players mp JOIN matches m ON m.id = mp.match_id
       WHERE mp.player_id = ? ORDER BY m.updated DESC LIMIT 100`,
    ).bind(m[1]).all();
    return json({
      matches: (rows.results || []).map((r) => ({ id: r.id, updated: r.updated, finished: !!r.finished, title: r.title, summary: JSON.parse(r.summary) })),
    });
  }

  // A scorer sends the mobile numbers they typed for their players.
  // The list replaces what was there before. Numbers are hashed at once.
  if (p === '/v1/players/phones' && method === 'POST') {
    const scorer = await auth(request, env);
    const body = await readJson(request);
    const list = Array.isArray(body && body.players) ? body.players.slice(0, 3000) : [];
    const key = await phoneKey(env);
    const rows = [];
    for (const x of list) {
      if (!x || typeof x.id !== 'string' || !ID_RE.test(x.id)) continue;
      const d = cleanPhone(x.phone);
      if (!d) continue;
      rows.push({ id: x.id, h: await phoneHash(key, d), n: String(x.name ?? '').slice(0, 80), t: String(x.team ?? '').slice(0, 80) });
    }
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare('DELETE FROM player_phones WHERE scorer_id = ?').bind(scorer),
      env.DB.prepare(
        `INSERT OR REPLACE INTO player_phones (scorer_id, player_id, phone_hash, name, team)
         SELECT ?, json_extract(value, '$.id'), json_extract(value, '$.h'), json_extract(value, '$.n'), json_extract(value, '$.t') FROM json_each(?)`,
      ).bind(scorer, JSON.stringify(rows)),
      // A profile whose number changed no longer belongs to the old person.
      env.DB.prepare(
        `DELETE FROM claims WHERE scorer_id = ? AND NOT EXISTS (
           SELECT 1 FROM player_phones pp JOIN users u ON u.id = claims.user_id
           WHERE pp.scorer_id = claims.scorer_id AND pp.player_id = claims.player_id AND pp.phone_hash = u.phone_hash)`,
      ).bind(scorer),
      // People already logged in with one of these numbers ask to be linked.
      env.DB.prepare(
        `INSERT OR IGNORE INTO claims (user_id, scorer_id, player_id, status, created)
         SELECT u.id, pp.scorer_id, pp.player_id, 'pending', ? FROM player_phones pp JOIN users u ON u.phone_hash = pp.phone_hash
         WHERE pp.scorer_id = ?`,
      ).bind(now, scorer),
    ]);
    return json({ ok: true, count: rows.length });
  }

  // A player logs in with Google. Answers a token for this phone.
  if (p === '/v1/login' && method === 'POST') {
    const body = await readJson(request);
    if (!body || typeof body.idToken !== 'string' || body.idToken.length > 8000) throw new HttpError(400, 'missing token');
    const g = await verifyGoogle(body.idToken, env);
    const id = 'g' + g.sub.replace(/[^A-Za-z0-9]/g, '').slice(0, 60);
    await env.DB.prepare(
      `INSERT INTO users (id, email, name, created) VALUES (?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET email = excluded.email, name = excluded.name`,
    ).bind(id, g.email.slice(0, 120), g.name.slice(0, 80), Date.now()).run();
    const token = randomString(40, TOKEN_ALPHABET);
    await env.DB.prepare('INSERT INTO sessions (token_hash, user_id, created) VALUES (?, ?, ?)').bind(await sha256(token), id, Date.now()).run();
    const user = await env.DB.prepare('SELECT id, email, name, phone_hash FROM users WHERE id = ?').bind(id).first();
    return json({ token: 'U' + token, ...(await meInfo(user, env)) });
  }

  if (p === '/v1/me' && method === 'GET') {
    const user = await userAuth(request, env);
    return json(await meInfo(user, env));
  }

  if (p === '/v1/me' && method === 'DELETE') {
    const h = request.headers.get('authorization') || '';
    const m2 = /^Bearer U([A-Za-z0-9]+)$/.exec(h);
    if (m2) await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(await sha256(m2[1])).run();
    return json({ ok: true });
  }

  // A player types their own mobile number. Every scorer who used that
  // number for a player gets a "is this them?" question.
  if (p === '/v1/me/phone' && method === 'PUT') {
    const user = await userAuth(request, env);
    const body = await readJson(request);
    const d = cleanPhone(body && body.phone);
    if (!d) throw new HttpError(400, 'bad phone');
    const h = await phoneHash(await phoneKey(env), d);
    const now = Date.now();
    const stmts = [];
    if (user.phone_hash !== h) stmts.push(env.DB.prepare('DELETE FROM claims WHERE user_id = ?').bind(user.id));
    stmts.push(env.DB.prepare('UPDATE users SET phone_hash = ? WHERE id = ?').bind(h, user.id));
    stmts.push(
      env.DB.prepare(
        `INSERT OR IGNORE INTO claims (user_id, scorer_id, player_id, status, created)
         SELECT ?, scorer_id, player_id, 'pending', ? FROM player_phones WHERE phone_hash = ?`,
      ).bind(user.id, now, h),
    );
    // Logging in on the scorer's own phone: their own players need no question.
    const own = await scorerFrom(body.scorer, env);
    if (own) stmts.push(env.DB.prepare("UPDATE claims SET status = 'ok' WHERE user_id = ? AND scorer_id = ?").bind(user.id, own));
    await env.DB.batch(stmts);
    return json(await meInfo({ ...user, phone_hash: h }, env));
  }

  // Questions waiting for this scorer: "X says this player is them".
  if (p === '/v1/claims' && method === 'GET') {
    const scorer = await auth(request, env);
    const rows = await env.DB.prepare(
      `SELECT c.user_id, c.player_id, u.email, u.name FROM claims c JOIN users u ON u.id = c.user_id
       WHERE c.scorer_id = ? AND c.status = 'pending' ORDER BY c.created LIMIT 50`,
    ).bind(scorer).all();
    return json({ claims: (rows.results || []).map((r) => ({ userId: r.user_id, playerId: r.player_id, email: r.email, name: r.name })) });
  }

  if (p === '/v1/claims' && method === 'POST') {
    const scorer = await auth(request, env);
    const body = await readJson(request);
    if (!body || typeof body.userId !== 'string' || typeof body.playerId !== 'string') throw new HttpError(400, 'missing');
    await env.DB.prepare('UPDATE claims SET status = ? WHERE scorer_id = ? AND user_id = ? AND player_id = ?')
      .bind(body.ok ? 'ok' : 'no', scorer, body.userId, body.playerId)
      .run();
    return json({ ok: true });
  }

  // Web pages for people without the app.
  if ((m = /^\/m\/([^/]+)$/.exec(p)) && method === 'GET') return html(matchPage(m[1]));

  throw new HttpError(404, 'not found');
}

function html(body) {
  return new Response(body, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
}

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

const STYLE = `
:root{--bg:#070F1E;--s1:#0E1B30;--s2:#142540;--ln:#1C2D47;--tx:#F2F5FA;--t2:#A9B6C9;--gd:#FFC94A;--lv:#FF4D4D}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:15px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:560px;margin:0 auto;padding:16px}
.card{background:var(--s1);border:1px solid var(--ln);border-radius:18px;padding:14px;margin-top:12px}
.hero{background:linear-gradient(165deg,#17325A,#0E1B30 62%);border:1px solid #234071;border-radius:24px;padding:16px}
.n{font-variant-numeric:tabular-nums;font-weight:800}
.big{font-size:44px;line-height:1}.t2{color:var(--t2)}.gold{color:var(--gd)}
.live{display:inline-flex;gap:6px;align-items:center;background:rgba(255,77,77,.14);color:#FF8080;border-radius:8px;padding:2px 9px;font-size:12px;font-weight:800}
.live i{width:6px;height:6px;border-radius:9px;background:var(--lv)}
table{width:100%;border-collapse:collapse;font-size:14px}th{color:var(--t2);font-size:12px;text-align:right;font-weight:700;padding:4px 0}
th:first-child,td:first-child{text-align:left}td{text-align:right;padding:7px 0;border-top:1px solid var(--ln)}
.balls span{display:inline-flex;width:28px;height:28px;border-radius:99px;background:var(--s2);align-items:center;justify-content:center;font-size:12px;font-weight:800;margin-right:4px}
.foot{color:var(--t2);font-size:12px;text-align:center;margin:20px 0}
.status{background:rgba(255,201,74,.10);color:var(--gd);border-radius:12px;padding:10px 12px;font-weight:800;margin-top:12px}
`;

function matchPage(id) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Live score · GullyScore</title><style>${STYLE}</style></head><body><main>
<div class="t2" style="font-weight:800">GullyScore</div>
<div id="app"><div class="card t2">Loading the score…</div></div>
<div class="foot">Scores update by themselves every few seconds. Scored live with the GullyScore app.</div>
</main><script>
const id=${JSON.stringify(id)};let since=0,last=null;
const e=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function draw(d){const s=d.summary;const cur=s.innings[s.innings.length-1];
let h='<div class="hero"><div style="display:flex;justify-content:space-between;align-items:center">'+(d.finished?'<span class="t2" style="font-weight:800">Result</span>':'<span class="live"><i></i>Live</span>')+'<span class="t2" style="font-size:12px">'+e(s.title)+'</span></div>';
for(const i of s.innings){h+='<div style="display:flex;justify-content:space-between;align-items:baseline;margin-top:12px"><b>'+e(i.team)+'</b><span class="n '+(i===cur?'big':'')+'">'+e(i.score)+' <span class="t2" style="font-size:15px">('+e(i.overs)+')</span></span></div>';}
h+='<div class="status">'+e(s.status)+'</div>';
if(s.thisOver&&s.thisOver.length){h+='<div class="balls" style="margin-top:12px">'+s.thisOver.map(b=>'<span>'+e(b==='•'?'0':b)+'</span>').join('')+'</div>';}
h+='</div>';
for(const i of [...s.innings].reverse()){h+='<div class="card"><b>'+e(i.team)+' '+e(i.score)+' ('+e(i.overs)+')</b><table><tr><th>Batter</th><th>R</th><th>B</th><th>4s</th><th>6s</th></tr>';
for(const b of i.batting){h+='<tr><td>'+e(b.name)+(b.onStrike?' *':'')+'<div class="t2" style="font-size:12px">'+e(b.out)+'</div></td><td class="n">'+b.r+'</td><td>'+b.b+'</td><td>'+b['4s']+'</td><td>'+b['6s']+'</td></tr>';}
h+='</table><table style="margin-top:8px"><tr><th>Bowler</th><th>O</th><th>M</th><th>R</th><th>W</th></tr>';
for(const b of i.bowling){h+='<tr><td>'+e(b.name)+'</td><td>'+e(b.o)+'</td><td>'+b.m+'</td><td>'+b.r+'</td><td class="n gold">'+b.w+'</td></tr>';}
h+='</table><div class="t2" style="font-size:12px;margin-top:6px">Extras '+e(i.extras)+'</div></div>';}
document.getElementById('app').innerHTML=h;}
async function tick(){try{const r=await fetch('/v1/matches/'+encodeURIComponent(id)+(since?'?since='+since:''));
if(r.status===404){document.getElementById('app').innerHTML='<div class="card">This match link is not available.</div>';return;}
const d=await r.json();if(!d.unchanged){since=d.updated;last=d;draw(d);}if(last&&last.finished)return;}catch(_){}
setTimeout(tick,5000);}tick();
</script></body></html>`;
}
