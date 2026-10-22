// Small helpers shared by all parts of the service.

export const MAX_BODY = 600 * 1024; // a long match is ~50 KB; this leaves room
export const ID_RE = /^[A-Za-z0-9_\-]{1,80}$/;
export const TOKEN_ALPHABET = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function json(body, status = 200, extra = {}) {
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

export async function readJson(request) {
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

export function randomString(n, alphabet) {
  const bytes = new Uint8Array(n);
  crypto.getRandomValues(bytes);
  let s = '';
  for (const b of bytes) s += alphabet[b % alphabet.length];
  return s;
}

export async function sha256(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Checks "Authorization: Bearer <scorerId>.<token>" and returns the scorer id. */
export async function auth(request, env) {
  const h = request.headers.get('authorization') || '';
  const m = /^Bearer ([A-Za-z0-9_\-]+)\.([A-Za-z0-9_\-]+)$/.exec(h);
  if (!m) throw new HttpError(401, 'not signed in');
  const row = await env.DB.prepare('SELECT token_hash FROM scorers WHERE id = ?').bind(m[1]).first();
  if (!row || row.token_hash !== (await sha256(m[2]))) throw new HttpError(401, 'not signed in');
  return m[1];
}

/** Checks "Authorization: Bearer U<token>" (a logged-in player) and returns the user row. */
export async function userAuth(request, env) {
  const h = request.headers.get('authorization') || '';
  const m = /^Bearer U([A-Za-z0-9]+)$/.exec(h);
  if (!m) throw new HttpError(401, 'not logged in');
  const row = await env.DB.prepare('SELECT u.id, u.email, u.name, u.phone_hash FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?')
    .bind(await sha256(m[1]))
    .first();
  if (!row) throw new HttpError(401, 'not logged in');
  return row;
}

export function html(body) {
  return new Response(body, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
}

export function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

/** Where a ground photo lives in the photo store (R2), when the account has one. */
export const photoKey = (groundId, photoId) => `grounds/${groundId}/${photoId}.jpg`;
