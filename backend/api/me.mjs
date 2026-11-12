import { allowedOrigins, authenticate, handleOptions, prepareApi, sendJson } from '../lib/api-http.mjs';
import { createRuntime } from '../lib/runtime.mjs';

export function createMeHandler({ verify, getMe, origins = allowedOrigins() } = {}) {
  return async function me(req, res) {
    if (handleOptions(req, res, ['GET'], origins)) return;
    if (!prepareApi(req, res, origins)) return sendJson(res, 403, { error: 'origin_not_allowed' });
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET, OPTIONS');
      return sendJson(res, 405, { error: 'method_not_allowed' });
    }
    if (!verify || !getMe) return sendJson(res, 503, { error: 'api_not_configured' });
    try {
      const identity = await authenticate(req, verify);
      if (!identity?.uid) return sendJson(res, 401, { error: 'session_invalid' });
      const account = await getMe(identity.uid);
      if (!account) return sendJson(res, 404, { error: 'account_not_found' });
      return sendJson(res, 200, { account });
    } catch {
      return sendJson(res, 503, { error: 'service_unavailable' });
    }
  };
}

const runtime = createRuntime();
export default createMeHandler(runtime ? {
  verify: runtime.verify,
  getMe: runtime.repository.getMe,
} : undefined);
