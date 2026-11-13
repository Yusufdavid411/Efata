import test from 'node:test';
import assert from 'node:assert/strict';
import { createSupabaseVerifier } from '../lib/supabase-auth.mjs';

test('verified Supabase users need an explicit EFATA account link', async () => {
  const id = '8dd6ff80-8097-4604-ad0b-c3240bed49a8';
  let identity = null;
  const verify = createSupabaseVerifier({
    url: 'https://example.test',
    key: 'public-key',
    findIdentity: async (subject) => {
      assert.equal(subject, id);
      return identity;
    },
    fetcher: async (url, options) => {
      assert.equal(url.pathname, '/auth/v1/user');
      assert.equal(options.headers.Authorization, 'Bearer access-token');
      return Response.json({ id, email_confirmed_at: '2026-11-13' });
    },
  });
  assert.equal(await verify('access-token'), null);
  identity = { uid: 'existing-efata-id' };
  assert.deepEqual(await verify('access-token'), identity);
});
