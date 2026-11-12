import {
  allowedOrigins, authenticate, handleOptions, prepareApi, readJson, sendJson,
} from '../lib/api-http.mjs';
import { ApiError } from '../lib/core-repository.mjs';
import { createRuntime } from '../lib/runtime.mjs';

const statuses = new Set(['pending', 'accepted', 'inTransit', 'completed', 'canceled']);

function coordinate(value, min, max) {
  return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
}

export function validateOrder(body) {
  const location = (value) => value && typeof value.label === 'string' &&
    value.label.trim().length > 0 && value.label.length <= 500 &&
    coordinate(value.lat, -90, 90) && coordinate(value.lng, -180, 180);
  if (!location(body.pickup) || !location(body.dropoff) ||
      typeof body.item !== 'string' || !body.item.trim() || body.item.length > 2000 ||
      typeof body.vehicleType !== 'string' || !body.vehicleType.trim() || body.vehicleType.length > 80 ||
      typeof body.paymentMethod !== 'string' || !body.paymentMethod.trim() || body.paymentMethod.length > 80 ||
      typeof body.amount !== 'number' || !Number.isFinite(body.amount) || body.amount < 0 || body.amount > 1e9) {
    return null;
  }
  let scheduledFor = null;
  if (body.scheduledFor != null) {
    const parsed = new Date(body.scheduledFor);
    if (Number.isNaN(parsed.valueOf())) return null;
    scheduledFor = parsed.toISOString();
  }
  return {
    pickup: { label: body.pickup.label.trim(), lat: body.pickup.lat, lng: body.pickup.lng },
    dropoff: { label: body.dropoff.label.trim(), lat: body.dropoff.lat, lng: body.dropoff.lng },
    item: body.item.trim(), vehicleType: body.vehicleType.trim(),
    paymentMethod: body.paymentMethod.trim(), amount: body.amount, scheduledFor,
  };
}

export function createOrdersHandler({ verify, listOrders, createOrder, origins = allowedOrigins() } = {}) {
  return async function orders(req, res) {
    if (handleOptions(req, res, ['GET', 'POST'], origins)) return;
    if (!prepareApi(req, res, origins)) return sendJson(res, 403, { error: 'origin_not_allowed' });
    if (!['GET', 'POST'].includes(req.method)) {
      res.setHeader('Allow', 'GET, POST, OPTIONS');
      return sendJson(res, 405, { error: 'method_not_allowed' });
    }
    if (!verify || !listOrders || !createOrder) return sendJson(res, 503, { error: 'api_not_configured' });
    try {
      const identity = await authenticate(req, verify);
      if (!identity?.uid) return sendJson(res, 401, { error: 'session_invalid' });
      if (req.method === 'POST') {
        const order = validateOrder(await readJson(req));
        if (!order) return sendJson(res, 400, { error: 'invalid_order' });
        return sendJson(res, 201, { order: await createOrder({ uid: identity.uid, order }) });
      }
      const params = new URL(req.url, 'http://localhost').searchParams;
      const scope = params.get('scope') ?? 'mine';
      const page = Number(params.get('page') ?? '1');
      const status = params.get('status') || null;
      if (!['mine', 'available', 'all'].includes(scope) || !Number.isInteger(page) ||
          page < 1 || page > 100 || (status && !statuses.has(status))) {
        return sendJson(res, 400, { error: 'invalid_query' });
      }
      const result = await listOrders({ uid: identity.uid, scope, page, limit: 25, status });
      return sendJson(res, 200, result);
    } catch (error) {
      if (error instanceof ApiError || error?.statusCode) {
        return sendJson(res, error.statusCode, { error: error.code ?? error.message });
      }
      return sendJson(res, 503, { error: 'service_unavailable' });
    }
  };
}

const runtime = createRuntime();
export default createOrdersHandler(runtime ? {
  verify: runtime.verify,
  listOrders: runtime.repository.listOrders,
  createOrder: runtime.repository.createOrder,
} : undefined);
