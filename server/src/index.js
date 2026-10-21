// GullyScore online service (Cloudflare Worker + D1).
//
// Phones that score upload their matches here. Anyone with a match link can
// watch it live, in the app or in a browser. Players can link their own
// phone to their profile with an invite code and see all their matches.
// Photos never come here: they stay on the phones.

const MAX_BODY = 600 * 1024; // a long match is ~50 KB; this leaves room
const ID_RE = /^[A-Za-z0-9_\-]{1,80}$/;
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O, 1/I

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

  if (p === '/' || p === '/v1/health') return json({ ok: true, service: 'gullyscore' });

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

  // Scorer makes an invite code for one of their players.
  if (p === '/v1/invites' && method === 'POST') {
    const scorer = await auth(request, env);
    const body = await readJson(request);
    if (!body || typeof body.playerId !== 'string' || !ID_RE.test(body.playerId) || typeof body.name !== 'string') {
      throw new HttpError(400, 'missing player');
    }
    const old = await env.DB.prepare('SELECT code FROM invites WHERE player_id = ? AND scorer_id = ?').bind(body.playerId, scorer).first();
    if (old) return json({ code: old.code });
    for (let i = 0; i < 5; i++) {
      const code = randomString(8, CODE_ALPHABET);
      const r = await env.DB.prepare('INSERT OR IGNORE INTO invites (code, player_id, name, team, scorer_id, created) VALUES (?, ?, ?, ?, ?, ?)')
        .bind(code, body.playerId, body.name.slice(0, 80), typeof body.team === 'string' ? body.team.slice(0, 80) : '', scorer, Date.now())
        .run();
      if (r.meta && r.meta.changes) return json({ code });
    }
    throw new HttpError(500, 'could not make a code');
  }

  if ((m = /^\/v1\/invites\/([A-Za-z0-9]+)$/.exec(p)) && method === 'GET') {
    const row = await env.DB.prepare('SELECT player_id, name, team FROM invites WHERE code = ?').bind(m[1].toUpperCase()).first();
    if (!row) throw new HttpError(404, 'no such code');
    return json({ playerId: row.player_id, name: row.name, team: row.team });
  }

  // Web pages for people without the app.
  if ((m = /^\/m\/([^/]+)$/.exec(p)) && method === 'GET') return html(matchPage(m[1]));
  if ((m = /^\/p\/([A-Za-z0-9]+)$/.exec(p)) && method === 'GET') {
    const row = await env.DB.prepare('SELECT player_id, name, team FROM invites WHERE code = ?').bind(m[1].toUpperCase()).first();
    return html(invitePage(m[1].toUpperCase(), row));
  }

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
.code{font-size:34px;letter-spacing:6px;font-weight:800;color:var(--gd);text-align:center;margin:12px 0}
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

function invitePage(code, row) {
  const name = row ? esc(row.name) : '';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Your GullyScore profile</title><style>${STYLE}</style></head><body><main>
<div class="t2" style="font-weight:800">GullyScore</div>
${
  row
    ? `<div class="hero" style="margin-top:12px"><div class="t2">Profile for</div><div style="font-size:26px;font-weight:800">${name}</div>${
        row.team ? `<div class="t2">${esc(row.team)}</div>` : ''
      }</div>
<div class="card"><b>See all your matches on your phone</b><ol class="t2" style="padding-left:18px">
<li>Install and open the GullyScore app.</li><li>Go to <b>Profile → This is me</b>.</li><li>Enter this code:</li></ol>
<div class="code">${esc(code)}</div></div>`
    : `<div class="card">This invite code is not valid.</div>`
}
</main></body></html>`;
}
