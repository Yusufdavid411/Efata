import pg from 'pg';

let pool;

export function createHealthHandler(checkDatabase = async () => {
  const url = process.env.EFATA_READ_DATABASE_URL;
  if (!url) return false;
  pool ??= new pg.Pool({
    connectionString: url,
    max: 1,
    connectionTimeoutMillis: 3500,
    idleTimeoutMillis: 5000,
    statement_timeout: 3500,
    ssl: { rejectUnauthorized: true, ...(process.env.EFATA_DB_CA_PEM && { ca: process.env.EFATA_DB_CA_PEM }) },
  });
  await pool.query('select 1');
  return true;
}) {
  return async function health(req, res) {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET');
      res.statusCode = 405;
      return res.end(JSON.stringify({ error: 'method_not_allowed' }));
    }
    let ready = false;
    try { ready = await checkDatabase(); } catch { /* Do not expose database errors. */ }
    res.statusCode = ready ? 200 : 503;
    res.end(JSON.stringify({ service: 'efata-backend', status: ready ? 'ready' : 'not_ready' }));
  };
}

export default createHealthHandler();
