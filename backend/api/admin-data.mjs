import {
  allowedOrigins, authenticate, handleOptions, prepareApi, sendJson,
} from '../lib/api-http.mjs';
import { ApiError } from '../lib/core-repository.mjs';
import { createRuntime } from '../lib/runtime.mjs';

const resources = new Set(['drivers', 'users', 'orders', 'payouts', 'logs']);

export function createAdminDataHandler({
  verify, listAdminResource, origins = allowedOrigins(),
} = {}) {
  return async function adminData(req, res) {
    if (handleOptions(req, res, ['GET'], origins)) return;
    if (!prepareApi(req, res, origins)) return sendJson(res, 403, { error: 'origin_not_allowed' });
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET, OPTIONS');
      return sendJson(res, 405, { error: 'method_not_allowed' });
    }
    if (!verify || !listAdminResource) return sendJson(res, 503, { error: 'api_not_configured' });
    try {
      const identity = await authenticate(req, verify);
      if (!identity?.uid) return sendJson(res, 401, { error: 'session_invalid' });
      const params = new URL(req.url, 'http://localhost').searchParams;
      const resource = params.get('resource') ?? '';
      const page = Number(params.get('page') ?? '1');
      if (!resources.has(resource) || !Number.isInteger(page) || page < 1 || page > 1000) {
        return sendJson(res, 400, { error: 'invalid_query' });
      }
      return sendJson(res, 200, await listAdminResource({
        uid: identity.uid, resource, page, limit: 100,
      }));
    } catch (error) {
      if (error instanceof ApiError || error?.statusCode) {
        return sendJson(res, error.statusCode, { error: error.code ?? error.message });
      }
      return sendJson(res, 503, { error: 'service_unavailable' });
    }
  };
}

const runtime = createRuntime();
export default createAdminDataHandler(runtime ? {
  verify: runtime.verify,
  listAdminResource: runtime.repository.listAdminResource,
} : undefined);
