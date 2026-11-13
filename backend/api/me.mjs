import { allowedOrigins, authenticate, handleOptions, prepareApi, readJson, sendJson } from '../lib/api-http.mjs';
import { createRuntime } from '../lib/runtime.mjs';

export function createMeHandler({ verify, getMe, updateProfile, origins = allowedOrigins() } = {}) {
  return async function me(req, res) {
    if (handleOptions(req, res, ['GET', 'PATCH'], origins)) return;
    if (!prepareApi(req, res, origins)) return sendJson(res, 403, { error: 'origin_not_allowed' });
    if (!['GET', 'PATCH'].includes(req.method)) {
      res.setHeader('Allow', 'GET, PATCH, OPTIONS');
      return sendJson(res, 405, { error: 'method_not_allowed' });
    }
    if (!verify || !getMe) return sendJson(res, 503, { error: 'api_not_configured' });
    try {
      const identity = await authenticate(req, verify);
      if (!identity?.uid) return sendJson(res, 401, { error: 'session_invalid' });
      if (req.method === 'PATCH') {
        if (!updateProfile) return sendJson(res, 503, { error: 'api_not_configured' });
        const body = await readJson(req, 8192);
        const fields = { name: 120, phone: 40, address: 500, vehicleType: 80, plateNumber: 40, licenseUrl: 1000, photoUrl: 1000 };
        if (!body || Array.isArray(body) || typeof body !== 'object' ||
            !Object.keys(body).length || Object.entries(body).some(([key, value]) =>
              !Object.hasOwn(fields, key) || typeof value !== 'string' ||
              !value.trim() || value.length > fields[key])) {
          return sendJson(res, 400, { error: 'invalid_profile' });
        }
        for (const key of ['licenseUrl', 'photoUrl']) {
          if (body[key] && !/^https:\/\/res\.cloudinary\.com\/dk21bi5fg\/image\/upload\//.test(body[key])) {
            return sendJson(res, 400, { error: 'invalid_profile_asset' });
          }
        }
        return sendJson(res, 200, { account: await updateProfile(identity.uid, body) });
      }
      const account = await getMe(identity.uid);
      if (!account) return sendJson(res, 404, { error: 'account_not_found' });
      return sendJson(res, 200, { account });
    } catch (error) {
      return sendJson(res, error.statusCode ?? 503, { error: error.statusCode ? error.code ?? error.message : 'service_unavailable' });
    }
  };
}

const runtime = createRuntime();
export default createMeHandler(runtime ? {
  verify: runtime.verify,
  getMe: runtime.repository.getMe,
  updateProfile: runtime.repository.updateProfile,
} : undefined);
