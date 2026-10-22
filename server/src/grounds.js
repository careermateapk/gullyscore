// Grounds: near a place (phone location or an OpenStreetMap place search),
// filters, register with photos, reviews, matches played there and insights.
// No Google billing needed: maps and directions open in the Google Maps app.
import { matchItem } from './social.js';
import { HttpError, ID_RE, TOKEN_ALPHABET, json, randomString, readJson, userAuth } from './util.js';

export const PITCHES = ['turf', 'matting', 'cement', 'mud', 'astroturf'];
export const FACILITIES = ['lights', 'washrooms', 'water', 'nets', 'umpires', 'scorers', 'parking', 'pavilion', 'cafeteria', 'sightscreen', 'balls'];
const MAX_PHOTO = 400 * 1024; // base64 characters (~300 KB JPEG)
const MAX_PHOTOS = 12;
const MAP_DAYS = 14; // look an area up on the map again after this many days
const OVERPASS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];

const str = (v, n) => (typeof v === 'string' ? v.trim().slice(0, n) : '');
const num = (v) => (v === null || v === undefined || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));
const int = (v, lo, hi) => Math.max(lo, Math.min(hi, Math.trunc(Number(v) || 0)));
const list = (v, allowed) => (Array.isArray(v) ? [...new Set(v.filter((x) => allowed.includes(x)))] : []);
const parse = (t, d) => {
  try {
    return JSON.parse(t);
  } catch {
    return d;
  }
};

export function km(aLat, aLng, bLat, bLng) {
  const R = 6371;
  const dLat = ((bLat - aLat) * Math.PI) / 180;
  const dLng = ((bLng - aLng) * Math.PI) / 180;
  const x = Math.sin(dLat / 2) ** 2 + Math.cos((aLat * Math.PI) / 180) * Math.cos((bLat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}

async function stats(env, ids) {
  const out = {};
  if (!ids.length) return out;
  const q = ids.map(() => '?').join(',');
  const r = await env.DB.prepare(`SELECT ground_id, COUNT(*) AS n, AVG(stars) AS avg FROM ground_reviews WHERE ground_id IN (${q}) GROUP BY ground_id`).bind(...ids).all();
  const m = await env.DB.prepare(`SELECT ground_id, COUNT(*) AS n FROM matches WHERE ground_id IN (${q}) AND status != 'upcoming' GROUP BY ground_id`).bind(...ids).all();
  const p = await env.DB.prepare(`SELECT ground_id, MIN(id) AS pid, COUNT(*) AS n FROM ground_photos WHERE ground_id IN (${q}) GROUP BY ground_id`).bind(...ids).all();
  for (const id of ids) out[id] = { reviews: 0, rating: null, matches: 0, photo: null, photos: 0 };
  for (const x of r.results || []) Object.assign(out[x.ground_id], { reviews: x.n, rating: Math.round(x.avg * 10) / 10 });
  for (const x of m.results || []) out[x.ground_id].matches = x.n;
  for (const x of p.results || []) Object.assign(out[x.ground_id], { photo: x.pid, photos: x.n });
  return out;
}

function view(g, s, lat, lng) {
  return {
    id: g.id,
    name: g.name,
    address: g.address,
    city: g.city || '',
    lat: g.lat,
    lng: g.lng,
    pitches: parse(g.pitches, []).length ? parse(g.pitches, []) : g.pitch ? [g.pitch] : [],
    facilities: parse(g.facilities, []),
    feeMin: g.fee_min || 0,
    feeMax: g.fee_max || 0,
    fee: g.fee || '',
    boundaryMin: g.boundary_min || 0,
    boundaryMax: g.boundary_max || 0,
    timings: g.timings || '',
    phone: g.phone || '',
    phone2: g.phone2 || '',
    mine: false,
    fromMap: String(g.place_id || '').startsWith('osm:') && !g.user_id,
    km: lat == null || lng == null ? null : Math.round(km(lat, lng, g.lat, g.lng) * 10) / 10,
    ...(s || { reviews: 0, rating: null, matches: 0, photo: null, photos: 0 }),
  };
}

async function oneGround(env, id) {
  const g = await env.DB.prepare('SELECT * FROM grounds WHERE id = ? AND hidden = 0').bind(id).first();
  if (!g) throw new HttpError(404, 'no such ground');
  return g;
}

function groundFields(b) {
  const lat = num(b?.lat);
  const lng = num(b?.lng);
  const feeMin = int(b?.feeMin, 0, 1000000);
  const feeMax = Math.max(feeMin, int(b?.feeMax, 0, 1000000));
  return {
    name: str(b?.name, 100),
    address: str(b?.address, 200),
    city: str(b?.city, 80),
    lat,
    lng,
    pitches: list(b?.pitches, PITCHES),
    facilities: list(b?.facilities, FACILITIES),
    feeMin,
    feeMax,
    fee: str(b?.fee, 40),
    boundaryMin: int(b?.boundaryMin, 0, 200),
    boundaryMax: int(b?.boundaryMax, 0, 200),
    timings: str(b?.timings, 80),
    phone: String(b?.phone ?? '').replace(/[^\d+ ]/g, '').slice(0, 16),
    phone2: String(b?.phone2 ?? '').replace(/[^\d+ ]/g, '').slice(0, 16),
  };
}

function innRuns(score) {
  const m = /^(\d+)(?:\/(\d+))?/.exec(String(score || ''));
  return m ? Number(m[1]) : null;
}

async function insights(env, id) {
  const rows = await env.DB.prepare(
    "SELECT id, updated, summary, winner, team_a, team_b, team_a_name, team_b_name FROM matches WHERE ground_id = ? AND status = 'result' ORDER BY updated DESC LIMIT 500",
  ).bind(id).all();
  const ms = rows.results || [];
  let first = 0, firstN = 0, batFirstWins = 0, decided = 0;
  let high = null, low = null;
  const days = [0, 0, 0, 0, 0, 0, 0]; // Mon..Sun
  for (const m of ms) {
    const s = parse(m.summary, {});
    const inns = s.innings || [];
    for (const i of inns) {
      const r = innRuns(i.score);
      if (r == null) continue;
      if (!high || r > high.runs) high = { runs: r, score: i.score, team: i.team, overs: i.overs };
      if (!low || r < low.runs) low = { runs: r, score: i.score, team: i.team, overs: i.overs };
    }
    if (inns[0]) {
      const r = innRuns(inns[0].score);
      if (r != null) {
        first += r;
        firstN++;
      }
      if (m.winner && m.winner !== 'tie') {
        decided++;
        const winnerName = m.winner === m.team_a ? m.team_a_name : m.team_b_name;
        if (winnerName && winnerName === inns[0].team) batFirstWins++;
      }
    }
    const d = new Date(m.updated + 5.5 * 3600 * 1000).getUTCDay(); // India time, 0 = Sunday
    days[(d + 6) % 7]++;
  }
  const top = async (col) => {
    const r = await env.DB.prepare(
      `SELECT MAX(mp.name) AS name, SUM(mp.${col}) AS v FROM match_players mp JOIN matches m ON m.id = mp.match_id
       WHERE m.ground_id = ? AND m.status = 'result' AND mp.name != '' GROUP BY m.scorer_id, mp.player_id HAVING v > 0 ORDER BY v DESC LIMIT 3`,
    ).bind(id).all();
    return (r.results || []).map((x) => ({ name: x.name, value: x.v }));
  };
  return {
    matches: ms.length,
    avgFirst: firstN ? Math.round(first / firstN) : null,
    highest: high,
    lowest: low,
    batFirstWinPct: decided ? Math.round((batFirstWins * 100) / decided) : null,
    decided,
    days,
    topRuns: await top('runs'),
    topWickets: await top('wickets'),
  };
}

/** Place names (cities, areas) from OpenStreetMap, cached for a day. */
async function places(q, env) {
  if (env.FAKE_PLACES) return env.FAKE_PLACES(q); // tests
  const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&countrycodes=in&limit=6&accept-language=en&q=${encodeURIComponent(q)}`;
  const cache = typeof caches !== 'undefined' ? caches.default : null;
  const key = new Request(url);
  let res = cache ? await cache.match(key) : null;
  if (!res) {
    const r = await fetch(url, { headers: { 'user-agent': 'GullyScore/0.8 (cricket scoring app; grounds search)' } });
    if (!r.ok) return [];
    res = new Response(await r.text(), { headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=86400' } });
    if (cache) await cache.put(key, res.clone());
  }
  const list = await res.json();
  return list.map((x) => ({
    name: x.name || String(x.display_name || '').split(',')[0],
    detail: String(x.display_name || '').split(',').slice(1, 4).join(',').trim(),
    lat: Number(x.lat),
    lng: Number(x.lon),
  }));
}

/** Cricket grounds from OpenStreetMap around a point (raw Overpass elements). */
async function overpass(env, lat, lng, radiusKm, notes) {
  if (env.FAKE_OVERPASS) return env.FAKE_OVERPASS(lat, lng, radiusKm); // tests
  // A box is much quicker for the map servers than a circle.
  const dLat = radiusKm / 111;
  const dLng = radiusKm / (111 * Math.max(0.2, Math.cos((lat * Math.PI) / 180)));
  const box = `(${(lat - dLat).toFixed(4)},${(lng - dLng).toFixed(4)},${(lat + dLat).toFixed(4)},${(lng + dLng).toFixed(4)})`;
  const q = `[out:json][timeout:25];(nwr["sport"~"cricket"]${box};nwr["leisure"~"^(pitch|stadium|sports_centre)$"]["name"~"[Cc]ricket"]${box};);out center tags 400;`;
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), 25000);
  const ask = async (endpoint) => {
    const host = new URL(endpoint).host;
    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded', accept: 'application/json', 'user-agent': 'GullyScore/0.9 (cricket scoring app; grounds search)' },
        body: 'data=' + encodeURIComponent(q),
        signal: ac.signal,
      });
      if (!res.ok) throw new Error(`${host}:${res.status}`);
      const j = await res.json();
      if (j.remark && !(j.elements || []).length) throw new Error(`${host}:remark`); // busy or timed out
      notes.push(`${host}:ok:${(j.elements || []).length}`);
      return j.elements || [];
    } catch (e) {
      notes.push(String(e?.message || '').startsWith(host) ? e.message : `${host}:${e?.name || 'error'}`);
      throw e;
    }
  };
  try {
    // Ask all map servers at once and take the first good answer.
    const els = await Promise.any(OVERPASS.map(ask));
    ac.abort();
    return els;
  } catch {
    return null; // map not reachable now; try again next time
  } finally {
    clearTimeout(timer);
  }
}

const PLACE_KINDS = ['pitch', 'stadium', 'sports_centre', 'recreation_ground', 'park', 'track', 'sports_hall'];

/** Turn one map element into ground fields, or null if it is not a ground. */
export function mapGround(e) {
  const t = e.tags || {};
  const lat = e.lat ?? e.center?.lat;
  const lng = e.lon ?? e.center?.lon;
  if (lat == null || lng == null) return null;
  if (t.shop || t.amenity === 'school' && !t.leisure) return null;
  const sport = String(t.sport || '');
  const isPlace = PLACE_KINDS.includes(t.leisure) || t.landuse === 'recreation_ground' || t.club === 'sport';
  if (!isPlace) return null;
  let name = String(t.name || t['name:en'] || '').trim();
  if (!name) {
    // Unnamed pitches are often just a strip inside a park; keep only big ones.
    if (t.leisure !== 'stadium' && t.leisure !== 'sports_centre') return null;
    name = 'Cricket ground';
  }
  if (!/cricket/i.test(sport) && !/cricket/i.test(name)) return null;
  const addr = [t['addr:housenumber'], t['addr:street'], t['addr:suburb'] || t['addr:neighbourhood']].filter(Boolean).join(', ');
  const city = String(t['addr:city'] || t['addr:district'] || '').slice(0, 80);
  const surface = String(t.surface || '').toLowerCase();
  const pitches = /artificial|astroturf/.test(surface) ? ['astroturf'] : /grass/.test(surface) ? ['turf'] : /concrete|asphalt/.test(surface) ? ['cement'] : /dirt|earth|ground|sand/.test(surface) ? ['mud'] : [];
  const facilities = [];
  if (t.lit === 'yes') facilities.push('lights');
  if (t.toilets === 'yes') facilities.push('washrooms');
  const phone = String(t.phone || t['contact:phone'] || '').replace(/[^\d+ ]/g, '').slice(0, 16);
  return {
    placeId: `osm:${e.type}/${e.id}`,
    name: name.slice(0, 100),
    address: addr.slice(0, 200),
    city,
    lat: Number(lat),
    lng: Number(lng),
    pitches,
    facilities,
    timings: String(t.opening_hours || '').slice(0, 80),
    phone,
  };
}

/** Make sure map grounds around this point are in the grounds table. */
async function loadMapGrounds(env, lat, lng, radiusKm, notes = []) {
  if (env.NO_MAP) return;
  const r = Math.min(radiusKm, 30);
  const area = `v2:${lat.toFixed(2)},${lng.toFixed(2)},${r}`;
  const seen = await env.DB.prepare('SELECT fetched FROM map_areas WHERE area = ?').bind(area).first();
  if (seen && Date.now() - seen.fetched < MAP_DAYS * 86400000) {
    notes.push('cached');
    return;
  }
  const els = await overpass(env, lat, lng, r, notes);
  if (els == null || !els.length) return; // nothing back: try again next time
  const now = Date.now();
  const stmts = [];
  for (const e of els) {
    const g = mapGround(e);
    if (!g) continue;
    stmts.push(
      env.DB.prepare(
        `INSERT OR IGNORE INTO grounds (id, name, address, city, lat, lng, place_id, pitches, facilities, timings, phone, user_id, created)
         SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ? WHERE NOT EXISTS (SELECT 1 FROM grounds WHERE place_id = ?)`,
      ).bind('m' + g.placeId.slice(4, 5) + g.placeId.split('/')[1], g.name, g.address, g.city, g.lat, g.lng, g.placeId, JSON.stringify(g.pitches),
        JSON.stringify(g.facilities), g.timings, g.phone, now, g.placeId),
    );
  }
  stmts.push(env.DB.prepare('INSERT INTO map_areas (area, fetched) VALUES (?, ?) ON CONFLICT(area) DO UPDATE SET fetched = excluded.fetched').bind(area, now));
  for (let i = 0; i < stmts.length; i += 50) await env.DB.batch(stmts.slice(i, i + 50));
}

export async function groundRoutes(p, method, url, request, env) {
  let m;
  // Places for the location picker.
  if (p === '/v1/places' && method === 'GET') {
    const q = str(url.searchParams.get('q'), 80);
    if (q.length < 2) return json({ places: [] });
    try {
      return json({ places: await places(q, env) });
    } catch {
      return json({ places: [] });
    }
  }

  // Grounds near a point, with filters and sorting.
  if (p === '/v1/grounds' && method === 'GET') {
    const lat = num(url.searchParams.get('lat'));
    const lng = num(url.searchParams.get('lng'));
    const radius = int(url.searchParams.get('km') || 15, 1, 200);
    const q = str(url.searchParams.get('q'), 80);
    let rows;
    const notes = [];
    if (q.length >= 2) {
      const like = '%' + q.replace(/[%_]/g, '') + '%';
      rows = await env.DB.prepare('SELECT * FROM grounds WHERE hidden = 0 AND (name LIKE ? OR address LIKE ? OR city LIKE ?) LIMIT 100').bind(like, like, like).all();
    } else if (lat != null && lng != null) {
      try {
        await loadMapGrounds(env, lat, lng, radius, notes);
      } catch (e) {
        notes.push('load:' + String(e?.message || e).slice(0, 60));
      }
      const d = radius / 100; // degrees ≈ km/111, a little wider
      rows = await env.DB.prepare('SELECT * FROM grounds WHERE hidden = 0 AND lat BETWEEN ? AND ? AND lng BETWEEN ? AND ? LIMIT 400')
        .bind(lat - d, lat + d, lng - d * 1.2, lng + d * 1.2)
        .all();
    } else {
      rows = await env.DB.prepare('SELECT * FROM grounds WHERE hidden = 0 ORDER BY created DESC LIMIT 100').all();
    }
    let gs = rows.results || [];
    const st = await stats(env, gs.map((g) => g.id));
    let out = gs.map((g) => view(g, st[g.id], lat, lng));
    if (lat != null && q.length < 2) out = out.filter((g) => g.km <= radius);
    const pitch = list((url.searchParams.get('pitch') || '').split(','), PITCHES);
    const fac = list((url.searchParams.get('fac') || '').split(','), FACILITIES);
    const feeMax = num(url.searchParams.get('feeMax'));
    if (pitch.length) out = out.filter((g) => g.pitches.some((x) => pitch.includes(x)));
    if (fac.length) out = out.filter((g) => fac.every((x) => g.facilities.includes(x)));
    if (feeMax != null) out = out.filter((g) => g.feeMin <= feeMax);
    const sort = url.searchParams.get('sort') || 'distance';
    const by = {
      distance: (a, b) => (a.km ?? 1e9) - (b.km ?? 1e9),
      rating: (a, b) => (b.rating ?? 0) - (a.rating ?? 0) || b.reviews - a.reviews,
      matches: (a, b) => b.matches - a.matches,
      fee: (a, b) => a.feeMin - b.feeMin,
      name: (a, b) => a.name.localeCompare(b.name),
    }[sort] || ((a, b) => (a.km ?? 1e9) - (b.km ?? 1e9));
    out.sort(by);
    const res = json({ total: out.length, grounds: out.slice(0, 60) });
    if (notes.length) res.headers.set('x-map', notes.join(' '));
    return res;
  }

  if (p === '/v1/grounds' && method === 'POST') {
    const user = await userAuth(request, env);
    const f = groundFields(await readJson(request));
    if (!f.name || f.lat == null || f.lng == null || Math.abs(f.lat) > 90 || Math.abs(f.lng) > 180) throw new HttpError(400, 'missing');
    const recent = await env.DB.prepare('SELECT COUNT(*) AS n FROM grounds WHERE user_id = ? AND created > ?').bind(user.id, Date.now() - 86400000).first();
    if ((recent?.n || 0) >= 10) throw new HttpError(429, 'too many today');
    const id = randomString(14, TOKEN_ALPHABET);
    await env.DB.prepare(
      `INSERT INTO grounds (id, name, address, city, lat, lng, pitches, facilities, fee_min, fee_max, fee, boundary_min, boundary_max, timings, phone, phone2, user_id, created)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(id, f.name, f.address, f.city, f.lat, f.lng, JSON.stringify(f.pitches), JSON.stringify(f.facilities), f.feeMin, f.feeMax, f.fee,
      f.boundaryMin, f.boundaryMax, f.timings, f.phone, f.phone2, user.id, Date.now()).run();
    const g = await oneGround(env, id);
    return json({ ...view(g, null, f.lat, f.lng), mine: true });
  }

  if ((m = /^\/v1\/grounds\/([A-Za-z0-9]+)$/.exec(p))) {
    const g = await oneGround(env, m[1]);
    if (method === 'GET') {
      const lat = num(url.searchParams.get('lat'));
      const lng = num(url.searchParams.get('lng'));
      const st = await stats(env, [g.id]);
      const photos = await env.DB.prepare('SELECT id FROM ground_photos WHERE ground_id = ? ORDER BY created LIMIT 50').bind(g.id).all();
      let mine = false;
      if (/^Bearer U/.test(request.headers.get('authorization') || '')) {
        try {
          mine = (await userAuth(request, env)).id === g.user_id;
        } catch {}
      }
      return json({ ...view(g, st[g.id], lat, lng), mine, photoIds: (photos.results || []).map((x) => x.id) });
    }
    if (method === 'PUT') {
      const user = await userAuth(request, env);
      if (g.user_id && user.id !== g.user_id) throw new HttpError(403, 'only who registered it can edit');
      if (!g.user_id) await env.DB.prepare("UPDATE grounds SET user_id = ? WHERE id = ? AND user_id = ''").bind(user.id, g.id).run(); // a map ground: first person to fill details looks after it
      const f = groundFields({ ...view(g), ...(await readJson(request)) });
      await env.DB.prepare(
        `UPDATE grounds SET name = ?, address = ?, city = ?, lat = ?, lng = ?, pitches = ?, facilities = ?, fee_min = ?, fee_max = ?, fee = ?,
         boundary_min = ?, boundary_max = ?, timings = ?, phone = ?, phone2 = ? WHERE id = ?`,
      ).bind(f.name || g.name, f.address, f.city, f.lat ?? g.lat, f.lng ?? g.lng, JSON.stringify(f.pitches), JSON.stringify(f.facilities), f.feeMin, f.feeMax, f.fee,
        f.boundaryMin, f.boundaryMax, f.timings, f.phone, f.phone2, g.id).run();
      return json({ ...view(await oneGround(env, g.id)), mine: true });
    }
  }

  // Photos
  if ((m = /^\/v1\/grounds\/([A-Za-z0-9]+)\/photos$/.exec(p)) && method === 'POST') {
    const user = await userAuth(request, env);
    const g = await oneGround(env, m[1]);
    const b = await readJson(request);
    const data = typeof b?.jpeg === 'string' ? b.jpeg.replace(/^data:image\/jpeg;base64,/, '') : '';
    if (!data || data.length > MAX_PHOTO || !/^[A-Za-z0-9+/=]+$/.test(data) || !data.startsWith('/9j/')) throw new HttpError(400, 'send a JPEG under 300 KB');
    const n = await env.DB.prepare('SELECT COUNT(*) AS n FROM ground_photos WHERE ground_id = ?').bind(g.id).first();
    if ((n?.n || 0) >= MAX_PHOTOS) throw new HttpError(409, 'this ground has enough photos');
    const id = Date.now().toString(36) + randomString(6, TOKEN_ALPHABET);
    await env.DB.prepare('INSERT INTO ground_photos (id, ground_id, user_id, data, created) VALUES (?, ?, ?, ?, ?)').bind(id, g.id, user.id, data, Date.now()).run();
    return json({ id });
  }

  if ((m = /^\/v1\/grounds\/([A-Za-z0-9]+)\/photos\/([A-Za-z0-9]+)$/.exec(p))) {
    if (method === 'GET') {
      const row = await env.DB.prepare('SELECT data FROM ground_photos WHERE id = ? AND ground_id = ?').bind(m[2], m[1]).first();
      if (!row) throw new HttpError(404, 'no photo');
      const bytes = Uint8Array.from(atob(row.data), (c) => c.charCodeAt(0));
      return new Response(bytes, { headers: { 'content-type': 'image/jpeg', 'cache-control': 'public, max-age=2592000, immutable' } });
    }
    if (method === 'DELETE') {
      const user = await userAuth(request, env);
      const row = await env.DB.prepare('SELECT ph.user_id, g.user_id AS owner FROM ground_photos ph JOIN grounds g ON g.id = ph.ground_id WHERE ph.id = ? AND ph.ground_id = ?')
        .bind(m[2], m[1])
        .first();
      if (!row) return json({ ok: true });
      if (row.user_id !== user.id && row.owner !== user.id) throw new HttpError(403, 'not yours');
      await env.DB.prepare('DELETE FROM ground_photos WHERE id = ?').bind(m[2]).run();
      return json({ ok: true });
    }
  }

  // Reviews
  if ((m = /^\/v1\/grounds\/([A-Za-z0-9]+)\/reviews$/.exec(p))) {
    const g = await oneGround(env, m[1]);
    if (method === 'GET') {
      const rows = await env.DB.prepare(
        'SELECT r.user_id, r.stars, r.body, r.created, u.name FROM ground_reviews r LEFT JOIN users u ON u.id = r.user_id WHERE r.ground_id = ? ORDER BY r.created DESC LIMIT 100',
      ).bind(g.id).all();
      return json({ reviews: (rows.results || []).map((r) => ({ name: r.name || 'Player', stars: r.stars, body: r.body, created: r.created })) });
    }
    if (method === 'POST') {
      const user = await userAuth(request, env);
      const b = await readJson(request);
      const stars = int(b?.stars, 1, 5);
      await env.DB.prepare(
        'INSERT INTO ground_reviews (ground_id, user_id, stars, body, created) VALUES (?, ?, ?, ?, ?) ON CONFLICT(ground_id, user_id) DO UPDATE SET stars = excluded.stars, body = excluded.body, created = excluded.created',
      ).bind(g.id, user.id, stars, str(b?.body, 600), Date.now()).run();
      return json({ ok: true });
    }
  }

  // Matches and tournaments played at the ground
  if ((m = /^\/v1\/grounds\/([A-Za-z0-9]+)\/matches$/.exec(p)) && method === 'GET') {
    const g = await oneGround(env, m[1]);
    const rows = await env.DB.prepare(
      `SELECT m.id, m.updated, m.finished, m.title, m.summary, m.status, m.scheduled, m.ground, m.team_a, m.team_b, m.team_a_name, m.team_b_name, m.winner
       FROM matches m WHERE m.ground_id = ? ORDER BY COALESCE(m.scheduled, m.updated) DESC LIMIT 60`,
    ).bind(g.id).all();
    const matches = (rows.results || []).map(matchItem);
    const tours = {};
    for (const x of matches) {
      if (!x.title) continue;
      const t = (tours[x.title] ||= { title: x.title, matches: 0, last: 0 });
      t.matches++;
      t.last = Math.max(t.last, x.updated);
    }
    return json({ matches, tournaments: Object.values(tours).sort((a, b) => b.last - a.last) });
  }

  if ((m = /^\/v1\/grounds\/([A-Za-z0-9]+)\/insights$/.exec(p)) && method === 'GET') {
    const g = await oneGround(env, m[1]);
    return json(await insights(env, g.id));
  }

  return null;
}

export { ID_RE };
