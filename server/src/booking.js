// Ground booking (owner lists slots, teams send requests, owner accepts) and
// the weather for match day (Open-Meteo, free, no key).
import { push, topic } from './push.js';
import { HttpError, TOKEN_ALPHABET, json, randomString, readJson, userAuth } from './util.js';

const str = (v, n) => (typeof v === 'string' ? v.trim().slice(0, n) : '');
const int = (v, lo, hi) => Math.max(lo, Math.min(hi, Math.trunc(Number(v) || 0)));
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_SLOTS = 12;

/** Today in India as YYYY-MM-DD, plus [days] more. */
export function indiaDates(days, now = Date.now()) {
  const out = [];
  for (let i = 0; i < days; i++) out.push(new Date(now + 5.5 * 3600000 + i * 86400000).toISOString().slice(0, 10));
  return out;
}

/** Monday = 0 … Sunday = 6 for a YYYY-MM-DD date. */
const weekday = (d) => (new Date(d + 'T00:00:00Z').getUTCDay() + 6) % 7;

const slotView = (s) => ({ id: s.id, label: s.label, start: s.start_min, end: s.end_min, price: s.price, days: s.days });

async function ground(env, id) {
  const g = await env.DB.prepare('SELECT id, name, user_id FROM grounds WHERE id = ? AND hidden = 0').bind(id).first();
  if (!g) throw new HttpError(404, 'no such ground');
  return g;
}

async function optionalUser(request, env) {
  if (!/^Bearer U/.test(request.headers.get('authorization') || '')) return null;
  try {
    return await userAuth(request, env);
  } catch {
    return null;
  }
}

function bookingView(b, { owner = false } = {}) {
  return {
    id: b.id,
    groundId: b.ground_id,
    groundName: b.ground_name || '',
    slotId: b.slot_id,
    slotLabel: b.label || '',
    start: b.start_min ?? null,
    end: b.end_min ?? null,
    price: b.price ?? 0,
    date: b.date,
    team: b.team,
    note: b.note,
    status: b.status,
    created: b.created,
    by: b.user_name || '',
    ...(owner ? { phone: b.phone } : {}),
  };
}

async function weather(env, lat, lng) {
  if (env.FAKE_WEATHER) return env.FAKE_WEATHER(lat, lng);
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat.toFixed(2)}&longitude=${lng.toFixed(2)}&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=Asia%2FKolkata&forecast_days=14`;
  const cache = typeof caches !== 'undefined' ? caches.default : null;
  const key = new Request(url);
  let res = cache ? await cache.match(key) : null;
  if (!res) {
    const r = await fetch(url, { headers: { 'user-agent': 'GullyScore/0.9 (cricket scoring app)' } });
    if (!r.ok) return [];
    res = new Response(await r.text(), { headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=3600' } });
    if (cache) await cache.put(key, res.clone());
  }
  const j = await res.json();
  const d = j.daily || {};
  return (d.time || []).map((date, i) => ({
    date,
    code: d.weather_code?.[i] ?? null,
    max: d.temperature_2m_max?.[i] ?? null,
    min: d.temperature_2m_min?.[i] ?? null,
    rain: d.precipitation_probability_max?.[i] ?? null,
  }));
}

export async function bookingRoutes(p, method, url, request, env) {
  let m;

  if (p === '/v1/weather' && method === 'GET') {
    const lat = Number(url.searchParams.get('lat'));
    const lng = Number(url.searchParams.get('lng'));
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) throw new HttpError(400, 'lat and lng');
    try {
      return json({ days: await weather(env, lat, lng) });
    } catch {
      return json({ days: [] });
    }
  }

  // Slots of a ground, with what is free on each of the next 14 days.
  if ((m = /^\/v1\/grounds\/([A-Za-z0-9]+)\/slots$/.exec(p))) {
    const g = await ground(env, m[1]);
    if (method === 'PUT') {
      const user = await userAuth(request, env);
      if (g.user_id !== user.id) throw new HttpError(403, 'only the owner can change slots');
      const b = await readJson(request);
      const list = Array.isArray(b?.slots) ? b.slots.slice(0, MAX_SLOTS) : [];
      const old = await env.DB.prepare('SELECT id FROM ground_slots WHERE ground_id = ?').bind(g.id).all();
      const keep = new Set((old.results || []).map((x) => x.id));
      const stmts = [];
      const ids = [];
      list.forEach((s, i) => {
        const start = int(s?.start, 0, 24 * 60 - 1);
        const end = int(s?.end, start + 1, 24 * 60);
        const id = typeof s?.id === 'string' && keep.has(s.id) ? s.id : randomString(10, TOKEN_ALPHABET);
        ids.push(id);
        stmts.push(
          env.DB.prepare(
            `INSERT INTO ground_slots (id, ground_id, label, start_min, end_min, price, days, sort) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET label = excluded.label, start_min = excluded.start_min, end_min = excluded.end_min, price = excluded.price, days = excluded.days, sort = excluded.sort`,
          ).bind(id, g.id, str(s?.label, 30), start, end, int(s?.price, 0, 1000000), int(s?.days ?? 127, 1, 127), i),
        );
      });
      const gone = [...keep].filter((x) => !ids.includes(x));
      for (const x of gone) stmts.push(env.DB.prepare('DELETE FROM ground_slots WHERE id = ?').bind(x));
      if (stmts.length) await env.DB.batch(stmts);
    } else if (method !== 'GET') {
      return null;
    }
    const user = await optionalUser(request, env);
    const slots = (await env.DB.prepare('SELECT * FROM ground_slots WHERE ground_id = ? ORDER BY sort, start_min').bind(g.id).all()).results || [];
    const dates = indiaDates(14);
    const taken = (await env.DB.prepare(
      `SELECT slot_id, date, status, user_id FROM bookings WHERE ground_id = ? AND date >= ? AND date <= ? AND status IN ('requested', 'accepted')`,
    ).bind(g.id, dates[0], dates[dates.length - 1]).all()).results || [];
    const pick = DATE_RE.test(url.searchParams.get('date') || '') ? url.searchParams.get('date') : dates[0];
    const statusOf = (slot, date) => {
      if (!(slot.days & (1 << weekday(date)))) return 'closed';
      const rows = taken.filter((t) => t.slot_id === slot.id && t.date === date);
      if (rows.some((t) => t.status === 'accepted')) return rows.some((t) => t.status === 'accepted' && user && t.user_id === user.id) ? 'mine' : 'booked';
      if (user && rows.some((t) => t.user_id === user.id)) return 'requested';
      return 'free';
    };
    return json({
      mine: !!user && user.id === g.user_id,
      date: pick,
      slots: slots.map((s) => ({ ...slotView(s), status: statusOf(s, pick) })),
      days: dates.map((d) => ({ date: d, free: slots.filter((s) => statusOf(s, d) === 'free').length })),
    });
  }

  // Ask for a slot.
  if ((m = /^\/v1\/grounds\/([A-Za-z0-9]+)\/bookings$/.exec(p)) && method === 'POST') {
    const user = await userAuth(request, env);
    const g = await ground(env, m[1]);
    const b = await readJson(request);
    const date = String(b?.date || '');
    if (!DATE_RE.test(date) || !indiaDates(30).includes(date)) throw new HttpError(400, 'pick a date in the next few weeks');
    const slot = await env.DB.prepare('SELECT * FROM ground_slots WHERE id = ? AND ground_id = ?').bind(String(b?.slotId || ''), g.id).first();
    if (!slot) throw new HttpError(404, 'no such slot');
    if (!(slot.days & (1 << weekday(date)))) throw new HttpError(409, 'the ground is closed then');
    const busy = await env.DB.prepare(`SELECT COUNT(*) AS n FROM bookings WHERE slot_id = ? AND date = ? AND status = 'accepted'`).bind(slot.id, date).first();
    if (busy?.n) throw new HttpError(409, 'already booked');
    const dup = await env.DB.prepare(`SELECT id FROM bookings WHERE slot_id = ? AND date = ? AND user_id = ? AND status = 'requested'`).bind(slot.id, date, user.id).first();
    if (dup) return json({ id: dup.id, status: 'requested' });
    const recent = await env.DB.prepare('SELECT COUNT(*) AS n FROM bookings WHERE user_id = ? AND created > ?').bind(user.id, Date.now() - 86400000).first();
    if ((recent?.n || 0) >= 20) throw new HttpError(429, 'too many requests today');
    const id = randomString(12, TOKEN_ALPHABET);
    const team = str(b?.team, 60);
    await env.DB.prepare(
      'INSERT INTO bookings (id, ground_id, slot_id, date, user_id, team, phone, note, status, created, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    ).bind(id, g.id, slot.id, date, user.id, team, String(b?.phone ?? '').replace(/[^\d+ ]/g, '').slice(0, 16), str(b?.note, 200), 'requested', Date.now(), Date.now()).run();
    if (g.user_id && g.user_id !== user.id) {
      await push(env, [topic('u', g.user_id)], `📅 Booking request · ${g.name}`, `${team || user.name || 'A team'} · ${date} · ${slot.label}`, { booking: id, ground: g.id });
    }
    return json({ id, status: 'requested' });
  }

  // My requests, and requests for grounds I look after.
  if (p === '/v1/bookings' && method === 'GET') {
    const user = await userAuth(request, env);
    const cols = `b.*, s.label, s.start_min, s.end_min, s.price, g.name AS ground_name, u.name AS user_name`;
    const from = `FROM bookings b LEFT JOIN ground_slots s ON s.id = b.slot_id LEFT JOIN grounds g ON g.id = b.ground_id LEFT JOIN users u ON u.id = b.user_id`;
    const asked = (await env.DB.prepare(`SELECT ${cols} ${from} WHERE b.user_id = ? ORDER BY b.date DESC, b.created DESC LIMIT 100`).bind(user.id).all()).results || [];
    const incoming = (await env.DB.prepare(`SELECT ${cols} ${from} WHERE g.user_id = ? AND b.user_id != ? ORDER BY CASE b.status WHEN 'requested' THEN 0 ELSE 1 END, b.date, b.created DESC LIMIT 200`)
      .bind(user.id, user.id)
      .all()).results || [];
    return json({ asked: asked.map((b) => bookingView(b)), incoming: incoming.map((b) => bookingView(b, { owner: true })) });
  }

  // Accept, decline (owner) or cancel (who asked).
  if ((m = /^\/v1\/bookings\/([A-Za-z0-9]+)$/.exec(p)) && method === 'POST') {
    const user = await userAuth(request, env);
    const b = await env.DB.prepare('SELECT b.*, g.user_id AS owner, g.name AS ground_name, s.label FROM bookings b JOIN grounds g ON g.id = b.ground_id LEFT JOIN ground_slots s ON s.id = b.slot_id WHERE b.id = ?')
      .bind(m[1])
      .first();
    if (!b) throw new HttpError(404, 'no such booking');
    const action = String((await readJson(request))?.action || '');
    const now = Date.now();
    if (action === 'cancel') {
      if (b.user_id !== user.id) throw new HttpError(403, 'not yours');
      await env.DB.prepare(`UPDATE bookings SET status = 'cancelled', updated = ? WHERE id = ?`).bind(now, b.id).run();
      if (b.owner && b.status === 'accepted') await push(env, [topic('u', b.owner)], `❌ Booking cancelled · ${b.ground_name}`, `${b.team} · ${b.date} · ${b.label || ''}`, { booking: b.id });
      return json({ ok: true, status: 'cancelled' });
    }
    if (action !== 'accept' && action !== 'decline') throw new HttpError(400, 'accept, decline or cancel');
    if (b.owner !== user.id) throw new HttpError(403, 'only the owner');
    if (b.status === 'cancelled') throw new HttpError(409, 'the team cancelled');
    if (action === 'accept') {
      const other = await env.DB.prepare(`SELECT id FROM bookings WHERE slot_id = ? AND date = ? AND status = 'accepted' AND id != ?`).bind(b.slot_id, b.date, b.id).first();
      if (other) throw new HttpError(409, 'already booked');
      await env.DB.batch([
        env.DB.prepare(`UPDATE bookings SET status = 'accepted', updated = ? WHERE id = ?`).bind(now, b.id),
        env.DB.prepare(`UPDATE bookings SET status = 'declined', updated = ? WHERE slot_id = ? AND date = ? AND status = 'requested' AND id != ?`).bind(now, b.slot_id, b.date, b.id),
      ]);
    } else {
      await env.DB.prepare(`UPDATE bookings SET status = 'declined', updated = ? WHERE id = ?`).bind(now, b.id).run();
    }
    await push(
      env,
      [topic('u', b.user_id)],
      action === 'accept' ? `✅ Booked · ${b.ground_name}` : `Booking not available · ${b.ground_name}`,
      `${b.date} · ${b.label || ''}`,
      { booking: b.id, ground: b.ground_id },
    );
    return json({ ok: true, status: action === 'accept' ? 'accepted' : 'declined' });
  }

  return null;
}
