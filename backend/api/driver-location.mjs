import {
  allowedOrigins, authenticate, handleOptions, prepareApi, readJson, sendJson,
} from '../lib/api-http.mjs';
import { ApiError } from '../lib/core-repository.mjs';
import { createRuntime } from '../lib/runtime.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function validLocation(value) {
  return value && typeof value.lat === 'number' && typeof value.lng === 'number' &&
    Number.isFinite(value.lat) && Number.isFinite(value.lng) &&
    value.lat >= -90 && value.lat <= 90 && value.lng >= -180 && value.lng <= 180 &&
    (value.heading == null || (typeof value.heading === 'number' &&
      Number.isFinite(value.heading) && value.heading >= 0 && value.heading <= 360));
}

export function createDriverLocationHandler({
  verify, updateDriverLocation, getDriverLocation, origins = allowedOrigins(),
} = {}) {
  return async function driverLocation(req, res) {
    if (handleOptions(req, res, ['GET', 'POST'], origins)) return;
    if (!prepareApi(req, res, origins)) return sendJson(res, 403, { error: 'origin_not_allowed' });
    if (!['GET', 'POST'].includes(req.method)) return sendJson(res, 405, { error: 'method_not_allowed' });
    if (!verify || !updateDriverLocation || !getDriverLocation) {
      return sendJson(res, 503, { error: 'api_not_configured' });
    }
    try {
      const identity = await authenticate(req, verify);
      if (!identity?.uid) return sendJson(res, 401, { error: 'session_invalid' });
      if (req.method === 'GET') {
        const orderId = new URL(req.url, 'http://localhost').searchParams.get('orderId') ?? '';
        if (!uuid.test(orderId)) return sendJson(res, 400, { error: 'invalid_order' });
        return sendJson(res, 200, { tracking: await getDriverLocation({ uid: identity.uid, orderId }) });
      }
      const body = await readJson(req, 16 * 1024);
      if (!validLocation(body)) return sendJson(res, 400, { error: 'invalid_location' });
      const tracking = await updateDriverLocation({
        uid: identity.uid,
        location: { lat: body.lat, lng: body.lng, heading: body.heading ?? null },
      });
      return sendJson(res, 200, { tracking });
    } catch (error) {
      if (error instanceof ApiError || error?.statusCode) {
        return sendJson(res, error.statusCode, { error: error.code ?? error.message });
      }
      return sendJson(res, 503, { error: 'service_unavailable' });
    }
  };
}

const runtime = createRuntime();
export default createDriverLocationHandler(runtime ? {
  verify: runtime.verify,
  updateDriverLocation: runtime.repository.updateDriverLocation,
  getDriverLocation: runtime.repository.getDriverLocation,
} : undefined);
