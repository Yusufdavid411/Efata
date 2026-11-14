import {
  allowedOrigins, authenticate, handleOptions, prepareApi, readJson, sendJson,
} from '../lib/api-http.mjs';
import { ApiError } from '../lib/core-repository.mjs';
import { createRuntime } from '../lib/runtime.mjs';
import authHandler from '../lib/auth-handler.mjs';
import confirmEmail from '../lib/confirm-email.mjs';

const roles = new Set(['customer', 'driver']);

export function createAccountBootstrapHandler({
  verify, bootstrapAccount, origins = allowedOrigins(),
} = {}) {
  return async function accountBootstrap(req, res) {
    if (handleOptions(req, res, ['POST'], origins)) return;
    if (!prepareApi(req, res, origins)) return sendJson(res, 403, { error: 'origin_not_allowed' });
    if (req.method !== 'POST') return sendJson(res, 405, { error: 'method_not_allowed' });
    if (!verify || !bootstrapAccount) return sendJson(res, 503, { error: 'api_not_configured' });
    try {
      const identity = await authenticate(req, verify);
      if (!identity?.uid) return sendJson(res, 401, { error: 'session_invalid' });
      const body = await readJson(req, 8 * 1024);
      const role = body.role ?? identity.registrationRole ?? null;
      if (role != null && !roles.has(role)) return sendJson(res, 400, { error: 'invalid_role' });
      const account = await bootstrapAccount({ identity, role });
      return sendJson(res, 200, { account });
    } catch (error) {
      if (error instanceof ApiError || error?.statusCode) {
        return sendJson(res, error.statusCode, { error: error.code ?? error.message });
      }
      return sendJson(res, 503, { error: 'service_unavailable' });
    }
  };
}

const runtime = createRuntime();
const bootstrapHandler = createAccountBootstrapHandler(runtime ? {
  verify: runtime.verifyRegistration,
  bootstrapAccount: runtime.repository.bootstrapAccount,
} : undefined);

export default function accountEndpoint(req, res) {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/confirm-email' ||
      url.searchParams.get('endpoint') === 'confirm-email') return confirmEmail(req, res);
  return (url.pathname === '/api/auth' || url.searchParams.get('endpoint') === 'auth'
    ? authHandler : bootstrapHandler)(req, res);
}
