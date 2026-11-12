import pg from 'pg';

if (!process.env.EFATA_DATABASE_URL) throw new Error('Missing EFATA_DATABASE_URL');
const client = new pg.Client({
  connectionString: process.env.EFATA_DATABASE_URL,
  ssl: {
    rejectUnauthorized: true,
    ...(process.env.EFATA_DB_CA_PEM && { ca: process.env.EFATA_DB_CA_PEM }),
  },
  connectionTimeoutMillis: 15_000,
});

await client.connect();
try {
  const counts = {};
  for (const table of [
    'accounts', 'customer_profiles', 'driver_profiles', 'orders',
    'order_messages', 'admin_logs', 'migration_runs',
  ]) {
    const result = await client.query(`select count(*)::integer count from efata.${table}`);
    counts[table] = result.rows[0].count;
  }
  const integrity = await client.query(`
    select
      count(*) filter (where status = 'completed' and (
        chat_closed_at is null or unread_for_customer <> 0 or unread_for_driver <> 0
      ))::integer as completed_chat_issues,
      count(*) filter (where status in ('accepted', 'inTransit'))::integer as active_orders
    from efata.orders
  `);
  if (counts.migration_runs !== 1 || integrity.rows[0].completed_chat_issues !== 0) {
    throw new Error('Core materialization integrity check failed');
  }
  console.log(JSON.stringify({ counts, integrity: integrity.rows[0] }, null, 2));
} finally {
  await client.end();
}
