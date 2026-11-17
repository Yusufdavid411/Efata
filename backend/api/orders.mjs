import {
  allowedOrigins, authenticate, handleOptions, prepareApi, readJson, sendJson,
} from '../lib/api-http.mjs';
import { ApiError } from '../lib/core-repository.mjs';
import { createRuntime } from '../lib/runtime.mjs';

const statuses = new Set(['pending', 'accepted', 'inTransit', 'completed', 'canceled']);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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
  let parcelPhoto = null;
  if (body.parcelPhoto != null) {
    const encoded = body.parcelPhoto;
    if (typeof encoded !== 'string' || encoded.length > 349528 ||
        !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) return null;
    const bytes = Buffer.from(encoded, 'base64');
    if (bytes.length > 256 * 1024 || bytes.toString('base64') !== encoded ||
        !(bytes.subarray(0, 3).toString('hex') === 'ffd8ff' ||
          bytes.subarray(0, 8).toString('hex') === '89504e470d0a1a0a')) return null;
    parcelPhoto = bytes;
  }
  if (body.scheduledFor != null) {
    const parsed = new Date(body.scheduledFor);
    if (typeof body.scheduledFor !== 'string' ||
        !Number.isFinite(parsed.valueOf()) || parsed.valueOf() <= Date.now()) return null;
    scheduledFor = parsed.toISOString();
  }
  return {
    pickup: { label: body.pickup.label.trim(), lat: body.pickup.lat, lng: body.pickup.lng },
    dropoff: { label: body.dropoff.label.trim(), lat: body.dropoff.lat, lng: body.dropoff.lng },
    item: body.item.trim(), vehicleType: body.vehicleType.trim(),
    paymentMethod: body.paymentMethod.trim(), amount: body.amount, scheduledFor,
    ...(parcelPhoto && { parcelPhoto }),
  };
}

export function createOrdersHandler({
  verify, listOrders, getOrder, createOrder, origins = allowedOrigins(),
} = {}) {
  return async function orders(req, res) {
    if (handleOptions(req, res, ['GET', 'POST'], origins)) return;
    if (!prepareApi(req, res, origins)) return sendJson(res, 403, { error: 'origin_not_allowed' });
    if (!['GET', 'POST'].includes(req.method)) {
      res.setHeader('Allow', 'GET, POST, OPTIONS');
      return sendJson(res, 405, { error: 'method_not_allowed' });
    }
    if (!verify || !listOrders || !getOrder || !createOrder) {
      return sendJson(res, 503, { error: 'api_not_configured' });
    }
    try {
      const identity = await authenticate(req, verify);
      if (!identity?.uid) return sendJson(res, 401, { error: 'session_invalid' });
      if (req.method === 'POST') {
        const order = validateOrder(await readJson(req, 384 * 1024));
        if (!order) return sendJson(res, 400, { error: 'invalid_order' });
        return sendJson(res, 201, { order: await createOrder({ uid: identity.uid, order }) });
      }
      const params = new URL(req.url, 'http://localhost').searchParams;
      const orderId = params.get('id');
      if (orderId != null) {
        if (!uuid.test(orderId)) return sendJson(res, 400, { error: 'invalid_order' });
        const includePhoto = params.get('includePhoto') === '1';
        return sendJson(res, 200, { order: await getOrder({
          uid: identity.uid, orderId, ...(includePhoto && { includePhoto }),
        }) });
      }
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
  getOrder: runtime.repository.getOrder,
  createOrder: runtime.repository.createOrder,
} : undefined);
