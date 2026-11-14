import test from 'node:test';
import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import { createConfirmEmailHandler } from '../lib/confirm-email.mjs';

test('confirmation only consumes the token on POST and never returns a session', async () => {
  const token = 'a'.repeat(64);
  let calls = 0;
  const handler = createConfirmEmailHandler({
    url: 'https://example.test', key: 'test',
    fetcher: async (url, request) => {
      calls++;
      assert.equal(url.pathname, '/auth/v1/verify');
      assert.deepEqual(JSON.parse(request.body), { type: 'email', token_hash: token });
      return new Response(JSON.stringify({ access_token: 'not-for-browser' }));
    },
  });
  const run = async (method, url, content) => {
    const req = Object.assign(Readable.from(content ? [content] : []), { method, url });
    const res = { statusCode: 200, setHeader() {}, end(html) { this.html = html; } };
    await handler(req, res);
    return res;
  };
  const preview = await run('GET', '/confirm-email?token_hash=' + token);
  assert.match(preview.html, /<form/);
  assert.equal(calls, 0);
  const confirmed = await run('POST', '/confirm-email', 'token_hash=' + token);
  assert.match(confirmed.html, /Email confirmed/);
  assert.doesNotMatch(confirmed.html, /not-for-browser/);
  assert.equal(calls, 1);
});
