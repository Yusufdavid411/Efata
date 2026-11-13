import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { test } from 'node:test';
import { createAdminActionHandler } from '../api/admin-action.mjs';
import { createAdminDataHandler } from '../api/admin-data.mjs';
import { createAccountBootstrapHandler } from '../api/account-bootstrap.mjs';
import { createDriverAvailabilityHandler } from '../api/driver-availability.mjs';
import { createDriverLocationHandler } from '../api/driver-location.mjs';
import { createMeHandler } from '../api/me.mjs';
import { createMessagesHandler } from '../api/messages.mjs';
import { createOrderActionHandler } from '../api/order-action.mjs';
import { createOrdersHandler, validateOrder } from '../api/orders.mjs';
import { ApiError } from '../lib/core-repository.mjs';

const auth = { Authorization: 'Bearer user.a.a' };
const origins = new Set(['https://admin.efata.io']);

function testServer(routes) {
  const server = createServer((req, res) => routes[req.url.split('?')[0]](req, res));
  server.listen(0, '127.0.0.1');
  return once(server, 'listening').then(() => ({
    server,
    url: `http://127.0.0.1:${server.address().port}`,
  }));
}

async function close(server) {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
}

test('me endpoint requires a verified session and exact admin origin', async () => {
  const handler = createMeHandler({
    origins,
    verify: async (token) => token === 'user.a.a' ? { uid: 'customer-id' } : null,
    getMe: async (uid) => ({ uid, role: 'customer' }),
  });
  const { server, url } = await testServer({ '/api/me': handler });
  try {
    assert.equal((await fetch(`${url}/api/me`)).status, 401);
    assert.equal((await fetch(`${url}/api/me`, {
      headers: { ...auth, Origin: 'https://evil.example' },
    })).status, 403);
    const result = await fetch(`${url}/api/me`, {
      headers: { ...auth, Origin: 'https://admin.efata.io' },
    });
    assert.equal(result.status, 200);
    assert.equal(result.headers.get('access-control-allow-origin'), 'https://admin.efata.io');
    assert.deepEqual(await result.json(), { account: { uid: 'customer-id', role: 'customer' } });
  } finally {
    await close(server);
  }
});

test('account bootstrap trusts verified identity and only accepts application roles', async () => {
  const calls = [];
  const identity = {
    uid: 'customer-id', email: 'customer@efata.io', displayName: 'Customer',
    emailVerified: true, provider: 'google.com',
  };
  const handler = createAccountBootstrapHandler({
    origins,
    verify: async () => identity,
    bootstrapAccount: async (command) => {
      calls.push(command);
      return { uid: command.identity.uid, role: command.role };
    },
  });
  const { server, url } = await testServer({ '/api/account-bootstrap': handler });
  try {
    const invalid = await fetch(`${url}/api/account-bootstrap`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ role: 'admin' }),
    });
    assert.equal(invalid.status, 400);
    assert.equal(calls.length, 0);
    const result = await fetch(`${url}/api/account-bootstrap`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ role: 'customer', uid: 'somebody-else' }),
    });
    assert.equal(result.status, 200);
    assert.deepEqual(calls[0], { identity, role: 'customer' });
  } finally {
    await close(server);
  }
});

test('orders endpoint validates creation and never accepts a caller-selected account', async () => {
  const calls = [];
  const handler = createOrdersHandler({
    origins,
    verify: async () => ({ uid: 'customer-id' }),
    listOrders: async (query) => ({ orders: [], query }),
    getOrder: async (query) => ({ id: query.orderId, uid: query.uid }),
    createOrder: async (command) => { calls.push(command); return { id: 'new-order' }; },
  });
  const { server, url } = await testServer({ '/api/orders': handler });
  try {
    const invalid = await fetch(`${url}/api/orders`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ customerId: 'somebody-else' }),
    });
    assert.equal(invalid.status, 400);
    const body = {
      customerId: 'somebody-else',
      pickup: { label: 'Pickup', lat: 7.8, lng: 6.7 },
      dropoff: { label: 'Drop-off', lat: 8.1, lng: 7.1 },
      item: 'Documents', vehicleType: 'Car', paymentMethod: 'Cash on Delivery', amount: 2500,
    };
    const created = await fetch(`${url}/api/orders`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    assert.equal(created.status, 201);
    assert.equal(calls[0].uid, 'customer-id');
    assert.equal(calls[0].order.customerId, undefined);
    const listed = await fetch(`${url}/api/orders?scope=available&page=2`, { headers: auth });
    assert.equal(listed.status, 200);
    assert.deepEqual((await listed.json()).query, {
      uid: 'customer-id', scope: 'available', page: 2, limit: 25, status: null,
    });
    const orderId = 'b917c25d-bbd4-4a58-8417-613e64c4ed76';
    const single = await fetch(`${url}/api/orders?id=${orderId}`, { headers: auth });
    assert.equal(single.status, 200);
    assert.deepEqual((await single.json()).order, { id: orderId, uid: 'customer-id' });
  } finally {
    await close(server);
  }
});

test('order actions use the authenticated uid and preserve domain errors', async () => {
  const calls = [];
  const handler = createOrderActionHandler({
    origins,
    verify: async () => ({ uid: 'driver-id' }),
    transitionOrder: async (command) => {
      calls.push(command);
      if (command.action === 'complete') throw new ApiError(409, 'order_cannot_complete');
      return { id: command.orderId, status: 'accepted' };
    },
  });
  const { server, url } = await testServer({ '/api/order-action': handler });
  const orderId = 'b917c25d-bbd4-4a58-8417-613e64c4ed76';
  try {
    const accepted = await fetch(`${url}/api/order-action`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ orderId, action: 'accept', uid: 'other-driver' }),
    });
    assert.equal(accepted.status, 200);
    assert.deepEqual(calls[0], { uid: 'driver-id', orderId, action: 'accept' });
    const conflict = await fetch(`${url}/api/order-action`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ orderId, action: 'complete' }),
    });
    assert.equal(conflict.status, 409);
    assert.deepEqual(await conflict.json(), { error: 'order_cannot_complete' });
  } finally {
    await close(server);
  }
});

test('order validation enforces coordinates and bounded business fields', () => {
  assert.equal(validateOrder({}), null);
  assert.equal(validateOrder({
    pickup: { label: 'A', lat: 100, lng: 0 }, dropoff: { label: 'B', lat: 0, lng: 0 },
    item: 'Box', vehicleType: 'Van', paymentMethod: 'Cash', amount: 10,
  }), null);
});

test('messages use the authenticated participant and preserve closed-chat errors', async () => {
  const calls = [];
  const handler = createMessagesHandler({
    origins,
    verify: async () => ({ uid: 'customer-id' }),
    listMessages: async (query) => ({ messages: [], query }),
    markMessagesRead: async (command) => { calls.push({ kind: 'read', ...command }); },
    sendMessage: async (command) => {
      calls.push({ kind: 'send', ...command });
      throw new ApiError(409, 'chat_closed');
    },
  });
  const { server, url } = await testServer({ '/api/messages': handler });
  const orderId = 'b917c25d-bbd4-4a58-8417-613e64c4ed76';
  try {
    const closed = await fetch(`${url}/api/messages`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ orderId, text: 'Delivered', uid: 'somebody-else' }),
    });
    assert.equal(closed.status, 409);
    assert.deepEqual(await closed.json(), { error: 'chat_closed' });
    assert.deepEqual(calls[0], {
      kind: 'send', uid: 'customer-id', orderId, body: 'Delivered',
    });

    const read = await fetch(`${url}/api/messages`, {
      method: 'PATCH', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ orderId, uid: 'somebody-else' }),
    });
    assert.equal(read.status, 200);
    assert.deepEqual(calls[1], { kind: 'read', uid: 'customer-id', orderId });
  } finally {
    await close(server);
  }
});

test('driver availability requires valid current coordinates when going online', async () => {
  const calls = [];
  const handler = createDriverAvailabilityHandler({
    origins,
    verify: async () => ({ uid: 'driver-id' }),
    setDriverAvailability: async (command) => {
      calls.push(command);
      if (command.online && !command.location) throw new ApiError(400, 'location_required');
      return { isOnline: command.online, ...command.location };
    },
  });
  const { server, url } = await testServer({ '/api/driver-availability': handler });
  try {
    const missing = await fetch(`${url}/api/driver-availability`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ online: true }),
    });
    assert.equal(missing.status, 400);
    assert.deepEqual(await missing.json(), { error: 'location_required' });

    const invalid = await fetch(`${url}/api/driver-availability`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ online: true, location: { lat: 91, lng: 7 } }),
    });
    assert.equal(invalid.status, 400);

    const online = await fetch(`${url}/api/driver-availability`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ online: true, location: { lat: 7.84, lng: 6.67, heading: 180 } }),
    });
    assert.equal(online.status, 200);
    assert.deepEqual(calls.at(-1), {
      uid: 'driver-id', online: true, location: { lat: 7.84, lng: 6.67, heading: 180 },
    });
  } finally {
    await close(server);
  }
});

test('driver location validates writes and restricts reads to authenticated identity', async () => {
  const calls = [];
  const handler = createDriverLocationHandler({
    origins,
    verify: async () => ({ uid: 'driver-id' }),
    updateDriverLocation: async (command) => { calls.push(command); return command.location; },
    getDriverLocation: async (command) => { calls.push(command); return { lat: 7.84, lng: 6.67 }; },
  });
  const { server, url } = await testServer({ '/api/driver-location': handler });
  const orderId = 'b917c25d-bbd4-4a58-8417-613e64c4ed76';
  try {
    const invalid = await fetch(`${url}/api/driver-location`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ lat: 7.84, lng: 181 }),
    });
    assert.equal(invalid.status, 400);

    const updated = await fetch(`${url}/api/driver-location`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ lat: 7.84, lng: 6.67, heading: 45, uid: 'somebody-else' }),
    });
    assert.equal(updated.status, 200);
    assert.deepEqual(calls[0], {
      uid: 'driver-id', location: { lat: 7.84, lng: 6.67, heading: 45 },
    });

    const tracked = await fetch(`${url}/api/driver-location?orderId=${orderId}`, { headers: auth });
    assert.equal(tracked.status, 200);
    assert.deepEqual(calls[1], { uid: 'driver-id', orderId });
  } finally {
    await close(server);
  }
});

test('admin data uses the verified identity and accepts only known resources', async () => {
  const calls = [];
  const handler = createAdminDataHandler({
    origins,
    verify: async () => ({ uid: 'admin-id' }),
    listAdminResource: async (query) => { calls.push(query); return { rows: [] }; },
  });
  const { server, url } = await testServer({ '/api/admin-data': handler });
  try {
    assert.equal((await fetch(`${url}/api/admin-data?resource=secrets`, { headers: auth })).status, 400);
    const result = await fetch(`${url}/api/admin-data?resource=drivers&page=2&uid=other`, {
      headers: { ...auth, Origin: 'https://admin.efata.io' },
    });
    assert.equal(result.status, 200);
    assert.deepEqual(calls[0], {
      uid: 'admin-id', resource: 'drivers', page: 2, limit: 100,
    });
  } finally {
    await close(server);
  }
});

test('admin actions cannot override identity and preserve moderation errors', async () => {
  const calls = [];
  const handler = createAdminActionHandler({
    origins,
    verify: async () => ({ uid: 'admin-id' }),
    performAdminAction: async (command) => {
      calls.push(command);
      if (command.action === 'user-status') throw new ApiError(409, 'cannot_suspend_self');
      return { id: command.targetId, status: command.status };
    },
  });
  const { server, url } = await testServer({ '/api/admin-action': handler });
  const targetId = 'b917c25d-bbd4-4a58-8417-613e64c4ed76';
  try {
    const approved = await fetch(`${url}/api/admin-action`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'driver-status', targetId, status: 'approved', uid: 'other-admin', note: 'Checked',
      }),
    });
    assert.equal(approved.status, 200);
    assert.deepEqual(calls[0], {
      uid: 'admin-id', action: 'driver-status', targetId, status: 'approved',
      note: 'Checked', suspended: undefined,
    });

    const conflict = await fetch(`${url}/api/admin-action`, {
      method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'user-status', targetId, suspended: true }),
    });
    assert.equal(conflict.status, 409);
    assert.deepEqual(await conflict.json(), { error: 'cannot_suspend_self' });
  } finally {
    await close(server);
  }
});
