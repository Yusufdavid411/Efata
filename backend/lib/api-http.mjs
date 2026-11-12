const defaultOrigins = ['https://admin.efata.io'];

export function allowedOrigins(env = process.env) {
  const configured = (env.EFATA_ALLOWED_ORIGINS ?? '').split(',')
    .map((value) => value.trim()).filter(Boolean);
  return new Set(configured.length ? configured : defaultOrigins);
}

export function prepareApi(req, res, origins = allowedOrigins()) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Vary', 'Origin');
  const origin = req.headers.origin;
  if (origin && !origins.has(origin)) return false;
  if (origin) res.setHeader('Access-Control-Allow-Origin', origin);
  return true;
}

export function sendJson(res, statusCode, body) {
  res.statusCode = statusCode;
  res.end(JSON.stringify(body));
}

export function bearerToken(req) {
  const auth = req.headers.authorization;
  if (typeof auth !== 'string' || auth.length > 8192) return null;
  return /^Bearer ([\w-]+\.[\w-]+\.[\w-]+)$/i.exec(auth)?.[1] ?? null;
}

export async function readJson(req, limit = 64 * 1024) {
  if (req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body)) return req.body;
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw Object.assign(new Error('body_too_large'), { statusCode: 413 });
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
  } catch {
    throw Object.assign(new Error('invalid_json'), { statusCode: 400 });
  }
}

export async function authenticate(req, verify) {
  const token = bearerToken(req);
  if (!token) return null;
  return verify(token);
}

export function handleOptions(req, res, methods, origins = allowedOrigins()) {
  if (req.method !== 'OPTIONS') return false;
  if (!prepareApi(req, res, origins)) {
    sendJson(res, 403, { error: 'origin_not_allowed' });
    return true;
  }
  res.setHeader('Access-Control-Allow-Methods', `${methods.join(', ')}, OPTIONS`);
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.statusCode = 204;
  res.end();
  return true;
}
