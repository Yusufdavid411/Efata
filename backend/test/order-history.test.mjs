import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { test } from 'node:test';
import { createOrderHistoryHandler } from '../api/order-history.mjs';
import { createPreviewVerifier } from '../lib/preview-auth.mjs';

const now = Math.floor(Date.now() / 1000);
const project = 'logistics-app-7f9ff';
const makeToken = (claims = {}) => 'a.' + Buffer.from(JSON.stringify({
  aud: project, iss: 'https://securetoken.google.com/' + project,
  sub: 'customer-id', exp: now + 3600, auth_time: now - 30,
  ...claims,
})).toString('base64url') + '.c';

test('the preview checks the project, sends the signed token to Google, and enforces revocation', async () => {
  let lookups = 0;
  let account = { localId: 'customer-id', validSince: String(now - 60) };
  const verify = createPreviewVerifier({ apiKey: 'test-key', fetcher: async (url, init) => {
    lookups++;
    assert.equal(url.origin, 'https://identitytoolkit.googleapis.com');
    assert.equal(url.pathname, '/v1/accounts:lookup');
    assert.deepEqual(JSON.parse(init.body), { idToken: makeToken() });
    assert.equal(init.redirect, 'error');
    return Response.json({ users: [account] });
  } });
  assert.equal(await verify(makeToken({ aud: 'other-project' })), null);
  assert.equal(await verify(makeToken({ exp: now - 1 })), null);
  assert.equal(await verify(makeToken({ firebase: { tenant: 'other' } })), null);
  assert.equal(lookups, 0);
  assert.deepEqual(await verify(makeToken()), {
    uid: 'customer-id', email: null, displayName: null, photoUrl: null,
    emailVerified: false, provider: null,
  });
  account = { ...account, validSince: String(now - 1) };
  assert.equal(await verify(makeToken()), null);
  account = { localId: 'customer-id', validSince: String(now - 60), disabled: true };
  assert.equal(await verify(makeToken()), null);
  account = { localId: 'different-id', validSince: String(now - 60) };
  assert.equal(await verify(makeToken()), null);
});

test('order history is opt-in and restricts requests to the authenticated participant or configured admin', async () => {
  const calls = [];
  const configured = createOrderHistoryHandler({
    verify: async (token) => token === 'admin.a.a' ? { uid: 'admin-id' } : { uid: 'customer-id' },
    read: async (query) => {
      calls.push(query);
      return { orders: [{ id: 'sample' }], asOf: '2026-11-09T09:00:00Z', nextPage: null };
    },
    adminUids: ['admin-id'],
    origins: ['http://127.0.0.1:5173'],
  });
  const disabled = createOrderHistoryHandler();
  const server = createServer((req, res) => (req.url.startsWith('/disabled') ? disabled : configured)(req, res));
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = 'http://127.0.0.1:' + server.address().port;
  const get = (path, headers = {}, method = 'GET') => fetch(base + path, { method, headers });
  const auth = { Authorization: 'Bearer user.a.a' };
  try {
    assert.equal((await get('/disabled')).status, 503);
    assert.equal((await get('/api/order-history')).status, 401);
    assert.equal((await get('/api/order-history?scope=admin', auth)).status, 403);
    assert.equal((await get('/api/order-history?page=0', auth)).status, 400);
    assert.equal((await get('/api/order-history', auth, 'POST')).status, 405);
    assert.equal((await get('/api/order-history', { ...auth, Origin: 'https://untrusted.example' })).status, 403);
    const preflight = await get('/api/order-history', { Origin: 'http://127.0.0.1:5173' }, 'OPTIONS');
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get('Access-Control-Allow-Origin'), 'http://127.0.0.1:5173');
    assert.deepEqual(calls, []);
    const result = await get('/api/order-history?scope=driver&uid=somebody-else', auth);
    assert.equal(result.status, 200);
    assert.equal(result.headers.get('Cache-Control'), 'no-store');
    assert.deepEqual((await result.json()).orders, [{ id: 'sample' }]);
    assert.deepEqual(calls[0], { uid: 'customer-id', scope: 'driver', page: 1, limit: 50 });
    assert.equal((await get('/api/order-history?scope=admin&page=2', { Authorization: 'Bearer admin.a.a' })).status, 200);
    assert.deepEqual(calls[1], { uid: 'admin-id', scope: 'admin', page: 2, limit: 50 });
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});
