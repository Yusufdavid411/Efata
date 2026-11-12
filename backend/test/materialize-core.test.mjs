import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  normalizeOrderStatus,
  normalizeRole,
  normalizeVerificationStatus,
} from '../scripts/materialize-core.mjs';

test('normalizes legacy lifecycle values into constrained EFATA values', () => {
  assert.equal(normalizeOrderStatus('in_transit'), 'inTransit');
  assert.equal(normalizeOrderStatus('rejected'), 'canceled');
  assert.equal(normalizeOrderStatus('delivered'), 'completed');
  assert.equal(normalizeOrderStatus('unknown'), 'pending');
  assert.equal(normalizeRole('ADMIN'), 'admin');
  assert.equal(normalizeRole('passenger'), 'customer');
  assert.equal(normalizeVerificationStatus('incomplete'), 'pending');
});
