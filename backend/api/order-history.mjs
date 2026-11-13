import { createRuntime } from '../lib/runtime.mjs';
import { createPreviewOrderReader } from '../lib/preview-orders.mjs';

export function createOrderHistoryHandler({ verify, read, adminUids = [], origins = [] } = {}) {
  const allowedOrigins = new Set(origins);
  const allowedAdmins = new Set(adminUids);
  return async function orderHistory(req, res) {
    const send = (code, body) => {
      res.statusCode = code;
      return res.end(JSON.stringify(body));
    };
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Vary', 'Origin');
    const origin = req.headers.origin;
    if (origin) {
      if (!allowedOrigins.has(origin)) return send(403, { error: 'origin_not_allowed' });
      res.setHeader('Access-Control-Allow-Origin', origin);
    }
    if (!verify || !read) return send(503, { error: 'preview_not_configured' });
    if (req.method === 'OPTIONS') {
      res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers', 'Authorization');
      res.statusCode = 204;
      return res.end();
    }
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET, OPTIONS');
      return send(405, { error: 'method_not_allowed' });
    }
    const auth = req.headers.authorization;
    const token = typeof auth === 'string' && auth.length <= 8192 &&
      /^Bearer ([\w-]+\.[\w-]+\.[\w-]+)$/i.exec(auth)?.[1];
    if (!token) return send(401, { error: 'sign_in_required' });

    const params = new URL(req.url, 'http://localhost').searchParams;
    const scope = params.get('scope') ?? 'customer';
    const page = Number(params.get('page') ?? '1');
    if (!['customer', 'driver', 'admin'].includes(scope) ||
        !Number.isInteger(page) || page < 1 || page > 100) {
      return send(400, { error: 'invalid_query' });
    }
    try {
      const identity = await verify(token);
      if (!identity?.uid) return send(401, { error: 'session_invalid' });
      if (scope === 'admin' && !allowedAdmins.has(identity.uid)) {
        return send(403, { error: 'admin_access_required' });
      }
      const data = await read({ uid: identity.uid, scope, page, limit: 50 });
      return send(200, data);
    } catch {
      return send(503, { error: 'preview_unavailable' });
    }
  };
}

const list = (name) => (process.env[name] ?? '').split(',').map((value) => value.trim()).filter(Boolean);
const env = process.env;
const runtime = env.EFATA_ORDER_PREVIEW === '1' &&
  env.EFATA_PREVIEW_DATABASE_URL && env.EFATA_PREVIEW_SNAPSHOT_ID
  ? createRuntime(env) : null;

export default createOrderHistoryHandler(runtime ? {
  verify: runtime.verify,
  read: createPreviewOrderReader({
    url: env.EFATA_PREVIEW_DATABASE_URL, ca: env.EFATA_DB_CA_PEM, snapshotId: env.EFATA_PREVIEW_SNAPSHOT_ID,
  }),
  origins: list('EFATA_PREVIEW_ORIGINS'),
  adminUids: list('EFATA_PREVIEW_ADMIN_UIDS'),
} : undefined);
