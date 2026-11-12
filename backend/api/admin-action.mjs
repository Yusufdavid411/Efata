import {
  allowedOrigins, authenticate, handleOptions, prepareApi, readJson, sendJson,
} from '../lib/api-http.mjs';
import { ApiError } from '../lib/core-repository.mjs';
import { createRuntime } from '../lib/runtime.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const actions = new Set(['driver-status', 'user-status', 'order-dispute', 'payout-status']);

export function createAdminActionHandler({
  verify, performAdminAction, origins = allowedOrigins(),
} = {}) {
  return async function adminAction(req, res) {
    if (handleOptions(req, res, ['POST'], origins)) return;
    if (!prepareApi(req, res, origins)) return sendJson(res, 403, { error: 'origin_not_allowed' });
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'POST, OPTIONS');
      return sendJson(res, 405, { error: 'method_not_allowed' });
    }
    if (!verify || !performAdminAction) return sendJson(res, 503, { error: 'api_not_configured' });
    try {
      const identity = await authenticate(req, verify);
      if (!identity?.uid) return sendJson(res, 401, { error: 'session_invalid' });
      const body = await readJson(req, 16 * 1024);
      if (!actions.has(body.action) || !uuid.test(body.targetId ?? '')) {
        return sendJson(res, 400, { error: 'invalid_action' });
      }
      const result = await performAdminAction({
        uid: identity.uid,
        action: body.action,
        targetId: body.targetId,
        status: body.status,
        note: typeof body.note === 'string' ? body.note.trim() : '',
        suspended: body.suspended,
      });
      return sendJson(res, 200, { result });
    } catch (error) {
      if (error instanceof ApiError || error?.statusCode) {
        return sendJson(res, error.statusCode, { error: error.code ?? error.message });
      }
      return sendJson(res, 503, { error: 'service_unavailable' });
    }
  };
}

const runtime = createRuntime();
export default createAdminActionHandler(runtime ? {
  verify: runtime.verify,
  performAdminAction: runtime.repository.performAdminAction,
} : undefined);
