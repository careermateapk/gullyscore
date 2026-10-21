// v0.7: grounds near you, search (our list + Google), add a ground.
// Google search uses a server key (env.PLACES_API_KEY) and a daily cap so
// usage stays inside Google's free monthly amount.
import { HttpError, TOKEN_ALPHABET, json, randomString, readJson, userAuth } from './util.js';

export const GOOGLE_DAILY_CAP = 1100; // ~33,000 a month, under the 35,000 free Text Search (Pro) calls

const str = (v, n) => (typeof v === 'string' ? v.trim().slice(0, n) : '');
const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : null);

function km(aLat, aLng, bLat, bLng) {
  const R = 6371;
  const dLat = ((bLat - aLat) * Math.PI) / 180;
  const dLng = ((bLng - aLng) * Math.PI) / 180;
  const x = Math.sin(dLat / 2) ** 2 + Math.cos((aLat * Math.PI) / 180) * Math.cos((bLat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}

function view(g, lat, lng) {
  return {
    id: g.id,
    name: g.name,
    address: g.address,
    lat: g.lat,
    lng: g.lng,
    placeId: g.place_id || null,
    pitch: g.pitch,
    fee: g.fee,
    phone: g.phone,
    lights: !!g.lights,
    toilet: !!g.toilet,
    km: lat == null || lng == null ? null : Math.round(km(lat, lng, g.lat, g.lng) * 10) / 10,
  };
}

/** One Google search, if today's cap allows. Returns [] when off, capped or failing. */
async function googleSearch(env, q, lat, lng) {
  const key = String(env.PLACES_API_KEY || '').trim();
  if (!key && !env.FAKE_PLACES) return [];
  const day = new Date().toISOString().slice(0, 10);
  const k = 'places:' + day;
  await env.DB.prepare("INSERT INTO config (k, v) VALUES (?, '0') ON CONFLICT(k) DO NOTHING").bind(k).run();
  const row = await env.DB.prepare('SELECT v FROM config WHERE k = ?').bind(k).first();
  if (Number(row?.v || 0) >= GOOGLE_DAILY_CAP) return [];
  await env.DB.prepare('UPDATE config SET v = CAST(v AS INTEGER) + 1 WHERE k = ?').bind(k).run();
  if (env.FAKE_PLACES) return env.FAKE_PLACES(q); // tests
  const body = { textQuery: q, languageCode: 'en', regionCode: 'IN', pageSize: 10 };
  if (lat != null && lng != null) body.locationBias = { circle: { center: { latitude: lat, longitude: lng }, radius: 30000 } };
  try {
    const r = await fetch('https://places.googleapis.com/v1/places:searchText', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'X-Goog-Api-Key': key,
        'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location',
      },
      body: JSON.stringify(body),
    });
    if (!r.ok) return [];
    const j = await r.json();
    return (j.places || []).map((pl) => ({
      placeId: pl.id,
      name: pl.displayName?.text || '',
      address: pl.formattedAddress || '',
      lat: pl.location?.latitude,
      lng: pl.location?.longitude,
    }));
  } catch {
    return [];
  }
}

export async function groundRoutes(p, method, url, request, env) {
  if (p === '/v1/grounds' && method === 'GET') {
    const lat = num(url.searchParams.get('lat'));
    const lng = num(url.searchParams.get('lng'));
    let rows;
    if (lat != null && lng != null) {
      const d = 0.6; // about 60 km box, then sorted by distance
      rows = await env.DB.prepare('SELECT * FROM grounds WHERE hidden = 0 AND lat BETWEEN ? AND ? AND lng BETWEEN ? AND ? LIMIT 200')
        .bind(lat - d, lat + d, lng - d, lng + d)
        .all();
    } else {
      rows = await env.DB.prepare('SELECT * FROM grounds WHERE hidden = 0 ORDER BY created DESC LIMIT 50').all();
    }
    const list = (rows.results || []).map((g) => view(g, lat, lng));
    if (lat != null) list.sort((a, b) => a.km - b.km);
    return json({ grounds: list.slice(0, 50), google: !!String(env.PLACES_API_KEY || '').trim() });
  }

  if (p === '/v1/grounds/search' && method === 'GET') {
    const q = str(url.searchParams.get('q'), 80);
    const lat = num(url.searchParams.get('lat'));
    const lng = num(url.searchParams.get('lng'));
    if (q.length < 2) throw new HttpError(400, 'too short');
    const like = '%' + q.replace(/[%_]/g, '') + '%';
    const rows = await env.DB.prepare('SELECT * FROM grounds WHERE hidden = 0 AND (name LIKE ? OR address LIKE ?) LIMIT 30').bind(like, like).all();
    const ours = (rows.results || []).map((g) => view(g, lat, lng));
    if (lat != null) ours.sort((a, b) => a.km - b.km);
    const known = new Set(ours.map((g) => g.placeId).filter(Boolean));
    const google = (await googleSearch(env, q, lat, lng))
      .filter((g) => g.placeId && !known.has(g.placeId) && Number.isFinite(g.lat))
      .map((g) => ({ ...g, km: lat == null ? null : Math.round(km(lat, lng, g.lat, g.lng) * 10) / 10 }));
    // Google places already in our list show as ours.
    if (google.length) {
      const ids = google.map((g) => g.placeId);
      const have = await env.DB.prepare(`SELECT * FROM grounds WHERE hidden = 0 AND place_id IN (${ids.map(() => '?').join(',')})`).bind(...ids).all();
      for (const g of have.results || []) ours.push(view(g, lat, lng));
      const haveIds = new Set((have.results || []).map((g) => g.place_id));
      return json({ ours, google: google.filter((g) => !haveIds.has(g.placeId)) });
    }
    return json({ ours, google: [] });
  }

  if (p === '/v1/grounds' && method === 'POST') {
    const user = await userAuth(request, env);
    const b = await readJson(request);
    const name = str(b?.name, 100);
    const lat = num(b?.lat);
    const lng = num(b?.lng);
    if (!name || lat == null || lng == null || Math.abs(lat) > 90 || Math.abs(lng) > 180) throw new HttpError(400, 'missing');
    const placeId = str(b?.placeId, 200);
    if (placeId) {
      const old = await env.DB.prepare('SELECT * FROM grounds WHERE place_id = ?').bind(placeId).first();
      if (old) return json(view(old, lat, lng));
    }
    const recent = await env.DB.prepare('SELECT COUNT(*) AS n FROM grounds WHERE user_id = ? AND created > ?').bind(user.id, Date.now() - 86400000).first();
    if ((recent?.n || 0) >= 20) throw new HttpError(429, 'too many today');
    const id = randomString(14, TOKEN_ALPHABET);
    await env.DB.prepare(
      'INSERT INTO grounds (id, name, address, lat, lng, place_id, pitch, fee, phone, lights, toilet, user_id, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    ).bind(id, name, str(b?.address, 200), lat, lng, placeId, str(b?.pitch, 20), str(b?.fee, 40), String(b?.phone ?? '').replace(/[^\d+ ]/g, '').slice(0, 16),
      b?.lights ? 1 : 0, b?.toilet ? 1 : 0, user.id, Date.now()).run();
    const row = await env.DB.prepare('SELECT * FROM grounds WHERE id = ?').bind(id).first();
    return json(view(row, lat, lng));
  }

  return null;
}
