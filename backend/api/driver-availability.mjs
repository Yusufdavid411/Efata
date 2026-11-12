import {
  allowedOrigins, authenticate, handleOptions, prepareApi, readJson, sendJson,
} from '../lib/api-http.mjs';
import { ApiError } from '../lib/core-repository.mjs';
import { createRuntime } from '../lib/runtime.mjs';

function location(value) {
  if (!value || typeof value.lat !== 'number' || typeof value.lng !== 'number' ||
      !Number.isFinite(value.lat) || !Number.isFinite(value.lng) ||
      value.lat < -90 || value.lat > 90 || value.lng < -180 || value.lng > 180) return null;
  const heading = value.heading == null ? null : Number(value.heading);
  if (heading != null && (!Number.isFinite(heading) || heading < 0 || heading > 360)) return null;
  return { lat: value.lat, lng: value.lng, heading };
}

export function createDriverAvailabilityHandler({
  verify, setDriverAvailability, origins = allowedOrigins(),
} = {}) {
  return async function driverAvailability(req, res) {
    if (handleOptions(req, res, ['POST'], origins)) return;
    if (!prepareApi(req, res, origins)) return sendJson(res, 403, { error: 'origin_not_allowed' });
    if (req.method !== 'POST') return sendJson(res, 405, { error: 'method_not_allowed' });
    if (!verify || !setDriverAvailability) return sendJson(res, 503, { error: 'api_not_configured' });
    try {
      const identity = await authenticate(req, verify);
      if (!identity?.uid) return sendJson(res, 401, { error: 'session_invalid' });
      const body = await readJson(req, 16 * 1024);
      const current = body.location == null ? null : location(body.location);
      if (typeof body.online !== 'boolean' || (body.location != null && !current)) {
        return sendJson(res, 400, { error: 'invalid_availability' });
      }
      const availability = await setDriverAvailability({
        uid: identity.uid, online: body.online, location: current,
      });
      return sendJson(res, 200, { availability });
    } catch (error) {
      if (error instanceof ApiError || error?.statusCode) {
        return sendJson(res, error.statusCode, { error: error.code ?? error.message });
      }
      return sendJson(res, 503, { error: 'service_unavailable' });
    }
  };
}

const runtime = createRuntime();
export default createDriverAvailabilityHandler(runtime ? {
  verify: runtime.verify,
  setDriverAvailability: runtime.repository.setDriverAvailability,
} : undefined);
