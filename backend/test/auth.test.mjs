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
  assert.deepEqual(calls.map(([path]) => path), [
    '/auth/v1/signup', '/auth/v1/token?grant_type=password',
    '/auth/v1/token?grant_type=refresh_token',
  ]);
});
