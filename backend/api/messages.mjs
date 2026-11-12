import {
  allowedOrigins, authenticate, handleOptions, prepareApi, readJson, sendJson,
} from '../lib/api-http.mjs';
import { ApiError } from '../lib/core-repository.mjs';
import { createRuntime } from '../lib/runtime.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function createMessagesHandler({
  verify, listMessages, sendMessage, markMessagesRead, origins = allowedOrigins(),
} = {}) {
  return async function messages(req, res) {
    if (handleOptions(req, res, ['GET', 'POST', 'PATCH'], origins)) return;
    if (!prepareApi(req, res, origins)) return sendJson(res, 403, { error: 'origin_not_allowed' });
    if (!['GET', 'POST', 'PATCH'].includes(req.method)) {
      res.setHeader('Allow', 'GET, POST, PATCH, OPTIONS');
      return sendJson(res, 405, { error: 'method_not_allowed' });
    }
    if (!verify || !listMessages || !sendMessage || !markMessagesRead) {
      return sendJson(res, 503, { error: 'api_not_configured' });
    }
    try {
      const identity = await authenticate(req, verify);
      if (!identity?.uid) return sendJson(res, 401, { error: 'session_invalid' });
      if (req.method === 'GET') {
        const params = new URL(req.url, 'http://localhost').searchParams;
        const orderId = params.get('orderId') ?? '';
        const page = Number(params.get('page') ?? '1');
        if (!uuid.test(orderId) || !Number.isInteger(page) || page < 1 || page > 100) {
          return sendJson(res, 400, { error: 'invalid_query' });
        }
        return sendJson(res, 200, await listMessages({
          uid: identity.uid, orderId, page, limit: 50,
        }));
      }
      const body = await readJson(req, 16 * 1024);
      if (!uuid.test(body.orderId ?? '')) return sendJson(res, 400, { error: 'invalid_order' });
      if (req.method === 'PATCH') {
        await markMessagesRead({ uid: identity.uid, orderId: body.orderId });
        return sendJson(res, 200, { read: true });
      }
      if (typeof body.text !== 'string' || !body.text.trim() || body.text.length > 4000) {
        return sendJson(res, 400, { error: 'invalid_message' });
      }
      return sendJson(res, 201, { message: await sendMessage({
        uid: identity.uid, orderId: body.orderId, body: body.text.trim(),
      }) });
    } catch (error) {
      if (error instanceof ApiError || error?.statusCode) {
        return sendJson(res, error.statusCode, { error: error.code ?? error.message });
      }
      return sendJson(res, 503, { error: 'service_unavailable' });
    }
  };
}

const runtime = createRuntime();
export default createMessagesHandler(runtime ? {
  verify: runtime.verify,
  listMessages: runtime.repository.listMessages,
  sendMessage: runtime.repository.sendMessage,
  markMessagesRead: runtime.repository.markMessagesRead,
} : undefined);
