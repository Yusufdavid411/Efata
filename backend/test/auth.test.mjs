import test from 'node:test';
import assert from 'node:assert/strict';
import { createAuthHandler } from '../lib/auth-handler.mjs';

test('auth routes registration, sign-in and refresh without allowing admin signup', async () => {
  const calls = [];
  const handler = createAuthHandler({
    url: 'https://example.test', key: 'test-key',
    fetcher: async (url, options) => {
      calls.push([url.pathname + url.search, JSON.parse(options.body)]);
      return Response.json({ access_token: 'access', refresh_token: 'refresh', expires_in: 3600 });
    },
  });
  async function post(body) {
    let result;
    const res = { setHeader() {}, end(raw) { result = JSON.parse(raw); } };
    await handler({ method: 'POST', headers: {}, body }, res);
    return [res.statusCode, result];
  }
  const credentials = { email: 'user@example.test', password: 'test-password-123' };
  assert.equal((await post({ action: 'register', ...credentials, role: 'admin' }))[0], 400);
  assert.equal(calls.length, 0);
  assert.deepEqual(await post({ action: 'register', ...credentials, role: 'driver' }),
    [202, { confirmationRequired: true }]);
  assert.deepEqual(await post({ action: 'sign_in', ...credentials }),
    [200, { accessToken: 'access', refreshToken: 'refresh', expiresIn: 3600 }]);
  assert.equal((await post({ action: 'refresh', refreshToken: 'refresh' }))[0], 200);
  assert.equal((await post({ action: 'google_exchange', code: 'code', verifier: 'short' }))[0], 400);
  const verifier = 'a'.repeat(43);
  assert.deepEqual(await post({ action: 'google_exchange', code: 'code', verifier }),
    [200, { accessToken: 'access', refreshToken: 'refresh', expiresIn: 3600 }]);
  assert.deepEqual(calls.at(-1)[1], { auth_code: 'code', code_verifier: verifier });
  assert.deepEqual(calls.map(([path]) => path), [
    '/auth/v1/signup', '/auth/v1/token?grant_type=password',
    '/auth/v1/token?grant_type=refresh_token', '/auth/v1/token?grant_type=pkce',
  ]);
});

test('Google exchange uses the trusted provider and rejects malformed tokens', async () => {
  const calls = [];
  const handler = createAuthHandler({ url: 'https://example.test', key: 'test-key',
    fetcher: async (url, options) => {
      calls.push([url.pathname + url.search, JSON.parse(options.body)]);
      return Response.json({ access_token: 'access', refresh_token: 'refresh', expires_in: 3600 });
    },
  });
  const post = async (body) => {
    let result;
    const res = { setHeader() {}, end(raw) { result = JSON.parse(raw); } };
    await handler({ method: 'POST', headers: {}, body }, res);
    return [res.statusCode, result];
  };
  assert.equal((await post({ action: 'google', idToken: 'short' }))[0], 400);
  assert.equal(calls.length, 0);
  const token = 'a'.repeat(200);
  assert.equal((await post({ action: 'google', idToken: token, provider: 'untrusted', role: 'admin' }))[0], 200);
  assert.deepEqual(calls, [['/auth/v1/token?grant_type=id_token', { provider: 'google', id_token: token }]]);
});

test('failed Google identity verification never creates an application session', async () => {
  const handler = createAuthHandler({ url: 'https://example.test', key: 'test-key',
    fetcher: async () => Response.json({ code: 'provider_disabled', message: 'internal provider detail' }, { status: 400 }),
  });
  let body;
  const res = { setHeader() {}, end(raw) { body = JSON.parse(raw); } };
  await handler({ method: 'POST', headers: {}, body: { action: 'google', idToken: 'a'.repeat(200) } }, res);
  assert.equal(res.statusCode, 401);
  assert.deepEqual(body, { error: 'google_not_configured' });
});
