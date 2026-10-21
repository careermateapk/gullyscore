// Checks the Firebase sender builds a correctly signed token request and message.
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import { push } from '../src/push.js';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
const env = { FIREBASE_SERVICE_ACCOUNT: JSON.stringify({ client_email: 'fcm@test.iam.gserviceaccount.com', private_key: pem, project_id: 'ca-world-test' }) };

const calls = [];
globalThis.fetch = async (url, init) => {
  calls.push({ url, init });
  if (url.startsWith('https://oauth2.googleapis.com/token')) {
    return new Response(JSON.stringify({ access_token: 'tok123', expires_in: 3600 }), { status: 200 });
  }
  return new Response('{}', { status: 200 });
};

await push(env, ['m.x.s', 't.s.a.s'], 'Hello', 'World', { matchId: 'x' });
assert.equal(calls.length, 2);
const assertion = new URLSearchParams(calls[0].init.body).get('assertion');
const [h, c, sig] = assertion.split('.');
const claims = JSON.parse(Buffer.from(c, 'base64url').toString());
assert.equal(claims.iss, 'fcm@test.iam.gserviceaccount.com');
assert.equal(claims.scope, 'https://www.googleapis.com/auth/firebase.messaging');
const ok = createVerify('RSA-SHA256').update(`${h}.${c}`).verify(publicKey, Buffer.from(sig, 'base64url'));
assert.ok(ok, 'JWT signature verifies');
assert.equal(calls[1].url, 'https://fcm.googleapis.com/v1/projects/ca-world-test/messages:send');
assert.equal(calls[1].init.headers.authorization, 'Bearer tok123');
const msg = JSON.parse(calls[1].init.body).message;
assert.equal(msg.condition, "'m.x.s' in topics || 't.s.a.s' in topics");
assert.equal(msg.data.matchId, 'x');
await push(env, ['u.g1'], 'Again', 'cached token');
assert.equal(calls.length, 3, 'token is reused');
assert.equal(JSON.parse(calls[2].init.body).message.topic, 'u.g1');
console.log('push tests passed');
