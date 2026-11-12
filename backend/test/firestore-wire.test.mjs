import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  decodeFirestoreDocument,
  decodeFirestoreFields,
  decodeFirestoreValue,
} from '../lib/firestore-wire.mjs';

test('decodes Firestore REST wire values without losing nested data', () => {
  assert.deepEqual(decodeFirestoreFields({
    name: { stringValue: 'EFATA' },
    enabled: { booleanValue: true },
    count: { integerValue: '12' },
    ratio: { doubleValue: 2.5 },
    empty: { nullValue: null },
    location: { geoPointValue: { latitude: 7.8, longitude: 6.7 } },
    tags: { arrayValue: { values: [{ stringValue: 'delivery' }] } },
    nested: { mapValue: { fields: { ok: { booleanValue: true } } } },
  }), {
    name: 'EFATA', enabled: true, count: 12, ratio: 2.5, empty: null,
    location: { latitude: 7.8, longitude: 6.7 },
    tags: ['delivery'], nested: { ok: true },
  });
});

test('preserves Firestore document timestamps as migration metadata', () => {
  assert.deepEqual(decodeFirestoreDocument({
    fields: { status: { stringValue: 'completed' } },
    createTime: '2026-01-01T00:00:00Z',
    updateTime: '2026-01-02T00:00:00Z',
  }), {
    status: 'completed',
    _firestoreCreateTime: '2026-01-01T00:00:00Z',
    _firestoreUpdateTime: '2026-01-02T00:00:00Z',
  });
  assert.equal(decodeFirestoreValue({ doubleValue: 'Infinity' }), Infinity);
});
