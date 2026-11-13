export function createSupabaseVerifier({ url, key, findIdentity, fetcher = fetch }) {
  const endpoint = new URL('/auth/v1/user', url);
  return async (token) => {
    const response = await fetcher(endpoint, {
      headers: { apikey: key, Authorization: 'Bearer ' + token },
      signal: AbortSignal.timeout(5000),
      redirect: 'error',
    });
    if ([400, 401, 403].includes(response.status)) return null;
    if (!response.ok) throw new Error('EFATA identity service unavailable');
    const user = await response.json();
    if (user.is_anonymous === true || !user.email_confirmed_at ||
        typeof user.id !== 'string' ||
        !/^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(user.id)) return null;
    return await findIdentity(user.id);
  };
}
