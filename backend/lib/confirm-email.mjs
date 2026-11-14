export function createConfirmEmailHandler({ url, key, fetcher = fetch } = {}) {
  return async function confirmEmail(req, res) {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
    const query = new URL(req.url, 'https://api.efata.io').searchParams;
    // Keep the token out of the POST URL and do not consume it on email scanner GETs.
    let token = query.get('token_hash') ?? '';
    if (req.method === 'POST') {
      if (req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body)) {
        token = typeof req.body.token_hash === 'string' ? req.body.token_hash : '';
      } else {
        let body = req.body?.toString() ?? '';
        if (req.body == null) {
          for await (const chunk of req) {
            body += chunk;
            if (body.length > 1024) { res.statusCode = 413; return res.end(); }
          }
        }
        if (body.length > 1024) { res.statusCode = 413; return res.end(); }
        token = new URLSearchParams(body).get('token_hash') ?? '';
      }
    }
    const valid = /^[A-Za-z0-9_-]{32,256}$/.test(token);
    let title = 'Confirm your email';
    let message = 'Confirm this address to finish setting up your EFATA account.';
    let action = valid && req.method === 'GET'
      ? `<form method="post" action="/confirm-email"><input type="hidden" name="token_hash" value="${token}"><button>Confirm email</button></form>`
      : '';
    if (req.method === 'POST' && valid && url && key) {
      try {
        const result = await fetcher(new URL('/auth/v1/verify', url), {
          method: 'POST', redirect: 'error', signal: AbortSignal.timeout(7000),
          headers: { apikey: key, 'Content-Type': 'application/json' },
          body: JSON.stringify({ type: 'email', token_hash: token }),
        });
        await result.body?.cancel();
        if (result.ok) {
          title = 'Email confirmed';
          message = 'Your EFATA account is ready. Open the app and sign in with your email and password.';
          action = '<a href="efata://login">Open EFATA</a>';
        } else if (result.status >= 500 || result.status === 429) res.statusCode = 503;
      } catch { res.statusCode = 503; }
    } else if (req.method === 'POST' && valid) res.statusCode = 503;
    if (!action) {
      if (res.statusCode === 503) {
        title = 'Confirmation temporarily unavailable';
        message = 'Try the link from your email again shortly.';
      } else {
        res.statusCode = ['GET', 'POST'].includes(req.method) ? 400 : 405;
        title = 'Confirmation link unavailable';
        message = 'This link is invalid, expired, or already used. If you already confirmed your email, sign in from the app.';
      }
      action = '<a href="efata://login">Open EFATA</a>';
    }
    return res.end(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title} | EFATA</title><style>body{font:16px system-ui,sans-serif;color:#142520;margin:0;background:#fff}main{max-width:32rem;margin:12vh auto;padding:24px}p{line-height:1.5}a,button{display:inline-block;background:#08665d;color:white;border:0;border-radius:8px;padding:12px 18px;text-decoration:none;font:inherit;cursor:pointer}</style><main><strong>EFATA</strong><h1>${title}</h1><p>${message}</p>${action}</main></html>`);
  };
}

export default createConfirmEmailHandler({
  url: process.env.EFATA_SUPABASE_URL,
  key: process.env.EFATA_SUPABASE_PUBLIC_KEY,
});
