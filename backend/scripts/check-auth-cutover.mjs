import pg from 'pg';

const { EFATA_DATABASE_URL, EFATA_DB_CA_PEM } = process.env;
if (!EFATA_DATABASE_URL) throw new Error('EFATA_DATABASE_URL is required');

const db = new pg.Client({
  connectionString: EFATA_DATABASE_URL,
  ssl: { rejectUnauthorized: true, ...(EFATA_DB_CA_PEM && { ca: EFATA_DB_CA_PEM }) },
  connectionTimeoutMillis: 8000,
  statement_timeout: 8000,
});

try {
  await db.connect();
  const { rows: [accounts] } = await db.query(`
    select count(*)::int as active,
           count(u.id) filter (where u.email_confirmed_at is not null)::int as confirmed,
           count(*) filter (where a.role = 'admin' and u.email_confirmed_at is not null)::int
             as confirmed_admins
    from efata.accounts a
    left join auth.users u on u.id = a.supabase_auth_id
    where a.account_status = 'active'
  `);
  const response = await fetch('https://api.efata.io/api/auth', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{}',
    signal: AbortSignal.timeout(8000),
    redirect: 'error',
  });
  const payload = await response.json().catch(() => ({}));
  const endpointReady = response.status === 400 && payload.error === 'invalid_request';
  const identityReady = accounts.active > 0 && accounts.active === accounts.confirmed &&
    accounts.confirmed_admins > 0;
  console.log(JSON.stringify({ ...accounts, authHttpStatus: response.status,
    endpointReady, identityReady }, null, 2));
  if (!endpointReady || !identityReady) process.exitCode = 1;
} finally {
  await db.end();
}
