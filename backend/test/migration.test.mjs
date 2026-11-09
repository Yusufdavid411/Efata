import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { test } from 'node:test';
import { createHealthHandler } from '../api/health.mjs';
import { canonicalJson, seal, unseal } from '../scripts/archive.mjs';
import { cloudinaryReferences, firebaseSource } from '../scripts/firebase-source.mjs';
import { accountMetadata } from '../scripts/import.mjs';

test('archives authenticate encrypted content and preserve Firestore wire types', () => {
  const key = randomBytes(32);
  const wire = { date: { timestampValue: '2026-01-01T12:00:00.123456Z' },
    count: { integerValue: '9223372036854775807' }, ratio: { doubleValue: 'NaN' } };
  const data = Buffer.from(canonicalJson(wire));
  const archive = seal(data, key);
  assert.deepEqual(unseal(archive, key), data);
  assert.notDeepEqual(seal(data, key), archive);
  archive[archive.length - 1] ^= 1;
  assert.throws(() => unseal(archive, key));
});

test('source preserves child documents under missing parents and holds one read time', async () => {
  const database = 'projects/example/databases/(default)';
  const time = '2026-11-09T00:00:00.000Z';
  const source = firebaseSource({ project: 'example', token: 'test', fetcher: async (url, options) => {
    const request = new URL(url);
    const body = options.body && JSON.parse(options.body);
    assert.equal(body?.readTime ?? request.searchParams.get('readTime'), time);
    const path = decodeURIComponent(request.pathname);
    const name = database + '/documents/orders/missing';
    if (path.endsWith('documents:listCollectionIds')) return Response.json({ collectionIds: ['orders'] });
    if (path.endsWith('/orders')) {
      assert.equal(request.searchParams.get('showMissing'), 'true');
      if (request.searchParams.has('pageToken')) return Response.json({});
      return Response.json({ documents: [{ name }], nextPageToken: 'p2' });
    }
    if (path.endsWith('/missing:listCollectionIds')) return Response.json({ collectionIds: ['messages'] });
    if (path.endsWith('/messages')) {
      return Response.json({ documents: [{ name: name + '/messages/m1', fields: {} }] });
    }
    return Response.json({});
  } });
  const records = await Array.fromAsync(source.documents(database, time));
  assert.deepEqual(records.map((x) => x.path), ['orders/missing/messages/m1']);
});

test('imports safe account fields without credentials or privileged claims', () => {
  assert.deepEqual(accountMetadata({
    localId: 'legacy-uid', passwordHash: 'private', salt: 'private',
    customAttributes: '{"admin":true}', providerUserInfo: [{ providerId: 'google.com', rawId: 'old-subject', token: 'secret' }],
  }), {
    localId: 'legacy-uid', providerUserInfo: [{ providerId: 'google.com', rawId: 'old-subject' }],
  });
});

test('only the EFATA Cloudinary delivery host and paths are downloaded', () => {
  const good = 'https://res.cloudinary.com/dk21bi5fg/image/upload/v1/example.jpg';
  const refs = cloudinaryReferences([good, { duplicate: good },
    'https://res.cloudinary.com/another-cloud/image/upload/v1/example.jpg',
    'https://res.cloudinary.com.evil.test/dk21bi5fg/image/upload/example.jpg']);
  assert.deepEqual([...refs], [good]);
});

test('health endpoint reports readiness without exposing a database error', async () => {
  const res = {
    headers: {}, setHeader(name, value) { this.headers[name] = value; },
    end(body) { this.body = JSON.parse(body); },
  };
  await createHealthHandler(async () => true)({ method: 'GET' }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.headers['Cache-Control'], 'no-store');
  await createHealthHandler(async () => { throw new Error('private'); })({ method: 'GET' }, res);
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.status, 'not_ready');
  await createHealthHandler(async () => true)({ method: 'POST' }, res);
  assert.equal(res.statusCode, 405);
});
