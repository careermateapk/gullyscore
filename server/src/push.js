// Notifications through Firebase Cloud Messaging (FCM). Phones subscribe to
// topics; the service never stores phone tokens. Topics:
//   m.<match>.<level>          a followed match
//   t.<scorer>.<team>.<level>  a team (players of the team)
//   u.<user>                   one logged-in person (replies, joins)
// Levels: s = start/result, w = wickets and 50s/100s, b = every four and six, a = "who is coming?".
// Needs env.FIREBASE_SERVICE_ACCOUNT (the JSON key); without it nothing is sent.

let cached = null; // { token, exp, project }

function b64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function accessToken(env) {
  if (cached && cached.exp > Date.now() + 60000) return cached;
  const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();
  const header = b64url(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = b64url(
    enc.encode(JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 })),
  );
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(`${header}.${claims}`)));
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${header}.${claims}.${b64url(sig)}`,
  });
  if (!r.ok) throw new Error('token ' + r.status);
  const j = await r.json();
  cached = { token: j.access_token, exp: Date.now() + (j.expires_in || 3600) * 1000, project: sa.project_id };
  return cached;
}

const safe = (s) => String(s).replace(/[^A-Za-z0-9\-_.~%]/g, '_').slice(0, 200);
export const topic = (...parts) => parts.map(safe).join('.');

/** Sends one notification to anyone subscribed to any of the topics (max 5). */
export async function push(env, topics, title, body, data = {}) {
  topics = [...new Set(topics)].slice(0, 5);
  if (!topics.length) return;
  const msg = {
    ...(topics.length === 1 ? { topic: topics[0] } : { condition: topics.map((t) => `'${t}' in topics`).join(' || ') }),
    notification: { title: String(title).slice(0, 120), body: String(body).slice(0, 240) },
    data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
    android: { priority: 'high' },
  };
  if (env.FAKE_PUSH) return env.FAKE_PUSH(msg); // tests
  if (!env.FIREBASE_SERVICE_ACCOUNT) return;
  try {
    const t = await accessToken(env);
    await fetch(`https://fcm.googleapis.com/v1/projects/${t.project}/messages:send`, {
      method: 'POST',
      headers: { authorization: 'Bearer ' + t.token, 'content-type': 'application/json' },
      body: JSON.stringify({ message: msg }),
    });
  } catch {
    // Notifications are best effort; scoring never fails because of them.
  }
}

function wickets(score) {
  const m = /\/(\d+)/.exec(String(score || ''));
  return m ? Number(m[1]) : 0;
}

/** What changed between two uploads of a match → notifications. */
export function matchEvents(old, cur) {
  const out = [];
  const title = cur.summary?.title || '';
  const inns = cur.summary?.innings || [];
  const oldInns = old?.summary?.innings || [];
  const last = inns[inns.length - 1];
  const scoreLine = last ? `${last.team} ${last.score} (${last.overs})` : '';
  if (cur.status === 'live' && old?.status !== 'live' && old?.status !== 'result') {
    out.push({ level: 's', title: '🏏 Match started', body: `${title}${cur.ground ? ' · ' + cur.ground : ''}` });
  }
  if (cur.status === 'result' && old?.status !== 'result') {
    out.push({ level: 's', title: '🏆 Result', body: `${cur.summary?.status || ''}\n${title}` });
    return out;
  }
  if (!old) return out;
  for (let i = 0; i < inns.length; i++) {
    const a = inns[i];
    const b = oldInns[i];
    if (!a) continue;
    if (wickets(a.score) > wickets(b?.score)) {
      out.push({ level: 'w', title: '🔴 WICKET!', body: `${a.team} ${a.score} (${a.overs}) · ${title}` });
    }
    const before = Object.fromEntries((b?.batting || []).map((x) => [x.name, x]));
    for (const bat of a.batting || []) {
      const was = before[bat.name] || { r: 0, '4s': 0, '6s': 0 };
      for (const mark of [100, 50]) {
        if (bat.r >= mark && was.r < mark) {
          out.push({ level: 'w', title: mark === 100 ? `💯 ${bat.name} hits a CENTURY!` : `⭐ ${bat.name} reaches 50!`, body: `${bat.r} (${bat.b}) · ${scoreLine}` });
          break;
        }
      }
      if ((bat['6s'] || 0) > (was['6s'] || 0)) out.push({ level: 'b', title: `💥 SIX! ${bat.name}`, body: `${bat.r} (${bat.b}) · ${scoreLine}` });
      else if ((bat['4s'] || 0) > (was['4s'] || 0)) out.push({ level: 'b', title: `🏏 FOUR! ${bat.name}`, body: `${bat.r} (${bat.b}) · ${scoreLine}` });
    }
  }
  return out;
}

/** Sends the notifications for a match upload (to the match's and both teams' topics). */
export async function notifyMatch(env, scorerId, matchId, old, cur) {
  const events = matchEvents(old, cur).slice(0, 4);
  for (const e of events) {
    const topics = [topic('m', matchId, e.level)];
    if (cur.teamA) topics.push(topic('t', scorerId, cur.teamA, e.level));
    if (cur.teamB) topics.push(topic('t', scorerId, cur.teamB, e.level));
    await push(env, topics, e.title, e.body, { matchId });
  }
}
