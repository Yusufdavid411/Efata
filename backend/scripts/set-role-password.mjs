import pg from 'pg';

const target = 'fwjxmutbsiokeevgvbat';
const allowedRoles = new Set(['efata_health_reader', 'efata_api_runtime']);
const pooler = new URL(process.env.EFATA_DB_POOLER_URL ?? '');
const role = process.env.EFATA_RUNTIME_ROLE;
const password = process.env.EFATA_RUNTIME_PASSWORD;

if (pooler.username !== `postgres.${target}` || !pooler.hostname.endsWith('.pooler.supabase.com')) {
  throw new Error('Refusing to connect to an unexpected Supabase project');
}
if (!allowedRoles.has(role) || !password || password.length < 32) {
  throw new Error('Invalid runtime role provisioning request');
}

const client = new pg.Client({
  host: pooler.hostname,
  port: Number(pooler.port || 5432),
  user: pooler.username,
  database: 'postgres',
  password: process.env.EFATA_DB_PASSWORD,
  ssl: { rejectUnauthorized: true },
  connectionTimeoutMillis: 15_000,
});

const quoteLiteral = (value) => `'${String(value).replaceAll("'", "''")}'`;

await client.connect();
try {
  const exists = await client.query('select 1 from pg_roles where rolname = $1', [role]);
  if (exists.rowCount !== 1) throw new Error(`Database role ${role} has not been migrated`);
  await client.query(`alter role ${role} login password ${quoteLiteral(password)}`);
} finally {
  await client.end();
}

