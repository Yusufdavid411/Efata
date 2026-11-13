import { allowedOrigins, bearerToken, handleOptions, prepareApi, readJson, sendJson } from './api-http.mjs';

export function createAuthHandler({
  url, key, fetcher = fetch, origins = allowedOrigins(),
} = {}) {
  return async (req, res) => {
    if (handleOptions(req, res, ['POST'], origins)) return;
    const send = (status, body) => sendJson(res, status, body);
    if (!prepareApi(req, res, origins)) return send(403, { error: 'origin_not_allowed' });
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'POST, OPTIONS');
      return send(405, { error: 'method_not_allowed' });
    }
    if (!url || !key) return send(503, { error: 'auth_not_configured' });
    try {
      const input = await readJson(req, 8192);
      const { action, password, role, refreshToken } = input ?? {};
      const email = typeof input?.email === 'string' ? input.email.trim().toLowerCase() : '';
      if (action === 'change_password') {
        const token = bearerToken(req);
        if (!token) return send(401, { error: 'session_required' });
        if (typeof password !== 'string' || password.length < 12 || password.length > 72 ||
            /^(.)\1+$/.test(password)) return send(400, { error: 'invalid_password' });
        const changed = await fetcher(new URL('/auth/v1/user', url), {
          method: 'PUT',
          headers: { apikey: key, Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
          body: JSON.stringify({ password }),
          signal: AbortSignal.timeout(7000),
          redirect: 'error',
        });
        await changed.body?.cancel();
        return changed.ok ? send(200, { changed: true })
          : send(changed.status === 401 ? 401 : changed.status === 429 ? 429 : 400,
            { error: 'password_change_failed' });
      }
      let path, body;
      if (action === 'refresh') {
        if (typeof refreshToken !== 'string' || !refreshToken || refreshToken.length > 4096) {
          return send(400, { error: 'invalid_request' });
        }
        path = '/auth/v1/token?grant_type=refresh_token';
        body = { refresh_token: refreshToken };
      } else {
        if (!['sign_in', 'register'].includes(action) ||
            email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
            typeof password !== 'string' || !password || password.length > 256) {
          return send(400, { error: 'invalid_request' });
        }
        if (action === 'register' && (password.length < 12 || !['customer', 'driver'].includes(role))) {
          return send(400, { error: 'invalid_registration' });
        }
        path = action === 'register' ? '/auth/v1/signup' : '/auth/v1/token?grant_type=password';
        body = { email, password, ...(action === 'register' && { data: { role } }) };
      }
      const response = await fetcher(new URL(path, url), {
        method: 'POST',
        headers: { apikey: key, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(7000),
        redirect: 'error',
      });
      if (response.status === 429) return send(429, { error: 'try_again_later' });
      const result = await response.json();
      if (!response.ok) {
        if (response.status >= 500) return send(503, { error: 'auth_unavailable' });
        return send(action === 'register' ? 400 : 401, {
          error: action === 'register' ? 'registration_failed'
            : result.code === 'email_not_confirmed' ? 'email_not_confirmed' : 'invalid_credentials',
        });
      }
      if (action === 'register') return send(202, { confirmationRequired: true });
      if (!result.access_token || !result.refresh_token) return send(503, { error: 'auth_unavailable' });
      return send(200, {
        accessToken: result.access_token,
        refreshToken: result.refresh_token,
        expiresIn: result.expires_in,
      });
    } catch (error) {
      return send(error.statusCode ?? 503, { error: error.statusCode ? error.message : 'auth_unavailable' });
    }
  };
}

export default createAuthHandler({
  url: process.env.EFATA_SUPABASE_URL,
  key: process.env.EFATA_SUPABASE_PUBLIC_KEY,
});
