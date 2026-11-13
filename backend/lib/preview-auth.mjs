const project = 'logistics-app-7f9ff';
const issuer = 'https://securetoken.google.com/' + project;

export function createPreviewVerifier({ apiKey, fetcher = fetch }) {
  const endpoint = new URL('https://identitytoolkit.googleapis.com/v1/accounts:lookup');
  endpoint.searchParams.set('key', apiKey);
  return async (token) => {
    let claims;
    try {
      claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
    } catch {
      return null;
    }
    const now = Math.floor(Date.now() / 1000);
    if (claims?.iss !== issuer || claims.aud !== project ||
        typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 128 ||
        !Number.isInteger(claims.exp) || claims.exp <= now ||
        !Number.isInteger(claims.auth_time) || claims.auth_time <= 0 || claims.auth_time > now ||
        claims.firebase?.tenant || claims.firebase?.sign_in_provider === 'anonymous') return null;

    // Google verifies the original signed token. Decoded fields alone grant no access.
    const response = await fetcher(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken: token }),
      signal: AbortSignal.timeout(5000),
      redirect: 'error',
    });
    if (response.status === 400 || response.status === 401) {
      const result = await response.json();
      const reason = result.error?.message;
      if (['INVALID_ID_TOKEN', 'TOKEN_EXPIRED', 'USER_DISABLED', 'USER_NOT_FOUND',
        'CREDENTIAL_TOO_OLD_LOGIN_AGAIN'].includes(reason)) return null;
      throw new Error('Identity verification request rejected');
    }
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error('Identity verification unavailable');
    }
    const { users } = await response.json();
    const account = Array.isArray(users) && users.length === 1 ? users[0] : null;
    const validSince = /^\d+$/.test(String(account?.validSince)) ? Number(account.validSince) : NaN;
    if (account?.localId !== claims.sub || account.disabled === true ||
        !Number.isSafeInteger(validSince) || validSince < 0 ||
        claims.auth_time < validSince) return null;
    const email = typeof account.email === 'string' ? account.email.trim().toLowerCase() : null;
    const displayName = typeof account.displayName === 'string' ? account.displayName.trim() : null;
    const photoUrl = typeof account.photoUrl === 'string' ? account.photoUrl.trim() : null;
    return {
      uid: claims.sub,
      email: email || null,
      displayName: displayName || null,
      photoUrl: photoUrl || null,
      emailVerified: account.emailVerified === true,
      provider: claims.firebase?.sign_in_provider ?? null,
    };
  };
}
