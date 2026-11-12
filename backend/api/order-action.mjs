import {
  allowedOrigins, authenticate, handleOptions, prepareApi, readJson, sendJson,
} from '../lib/api-http.mjs';
import { ApiError } from '../lib/core-repository.mjs';
import { createRuntime } from '../lib/runtime.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const actions = new Set(['accept', 'start', 'complete', 'cancel']);

export function createOrderActionHandler({ verify, transitionOrder, origins = allowedOrigins() } = {}) {
  return async function orderAction(req, res) {
    if (handleOptions(req, res, ['POST'], origins)) return;
    if (!prepareApi(req, res, origins)) return sendJson(res, 403, { error: 'origin_not_allowed' });
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'POST, OPTIONS');
      return sendJson(res, 405, { error: 'method_not_allowed' });
    }
    if (!verify || !transitionOrder) return sendJson(res, 503, { error: 'api_not_configured' });
    try {
      const identity = await authenticate(req, verify);
      if (!identity?.uid) return sendJson(res, 401, { error: 'session_invalid' });
      const body = await readJson(req, 16 * 1024);
      if (!uuid.test(body.orderId ?? '') || !actions.has(body.action)) {
        return sendJson(res, 400, { error: 'invalid_action' });
      }
      const order = await transitionOrder({ uid: identity.uid, orderId: body.orderId, action: body.action });
      return sendJson(res, 200, { order });
    } catch (error) {
      if (error instanceof ApiError || error?.statusCode) {
        return sendJson(res, error.statusCode, { error: error.code ?? error.message });
      }
      return sendJson(res, 503, { error: 'service_unavailable' });
    }
  };
}

const runtime = createRuntime();
export default createOrderActionHandler(runtime ? {
  verify: runtime.verify,
  transitionOrder: runtime.repository.transitionOrder,
} : undefined);
