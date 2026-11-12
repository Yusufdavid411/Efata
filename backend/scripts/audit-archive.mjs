import pg from 'pg';
import { decodeFirestoreDocument } from '../lib/firestore-wire.mjs';

const expectedProject = 'fwjxmutbsiokeevgvbat';

function connectionConfig() {
  const pooler = new URL(process.env.EFATA_DB_POOLER_URL ?? '');
  if (pooler.username !== `postgres.${expectedProject}` ||
      !pooler.hostname.endsWith('.pooler.supabase.com')) {
    throw new Error('The connection does not target the EFATA Supabase project');
  }
  if (!process.env.EFATA_DB_PASSWORD) throw new Error('Missing EFATA database password');
  return {
    host: pooler.hostname,
    port: Number(pooler.port || 6543),
    user: pooler.username,
    database: 'postgres',
    password: process.env.EFATA_DB_PASSWORD,
    ssl: { rejectUnauthorized: true },
    connectionTimeoutMillis: 15_000,
  };
}

const client = new pg.Client(connectionConfig());
await client.connect();
try {
  const snapshot = await client.query(`
    select id from efata_migration.snapshots
    order by imported_at desc limit 1
  `);
  if (!snapshot.rowCount) throw new Error('No Firebase archive snapshot found');

  const result = await client.query(`
    select
      regexp_replace(document_path, '/[^/]+', '/{id}', 'g') as path_pattern,
      count(distinct document_path)::integer as documents,
      coalesce(array_agg(distinct field order by field)
        filter (where field is not null), '{}') as fields
    from efata_migration.firestore_documents d
    left join lateral jsonb_object_keys(
      coalesce(d.document->'fields', '{}'::jsonb)
    ) field on true
    where snapshot_id = $1
    group by path_pattern
    order by path_pattern
  `, [snapshot.rows[0].id]);

  const enumRows = await client.query(`
    select document_path, document
    from efata_migration.firestore_documents
    where snapshot_id = $1 and split_part(document_path, '/', 1) in ('orders', 'users', 'drivers')
  `, [snapshot.rows[0].id]);
  const frequencies = {};
  for (const row of enumRows.rows) {
    const collection = row.document_path.split('/')[0];
    const data = decodeFirestoreDocument(row.document);
    for (const field of collection === 'orders'
      ? ['status', 'paymentStatus', 'paymentMethod']
      : collection === 'users' ? ['role'] : ['verificationStatus']) {
      if (data[field] == null) continue;
      const key = `${collection}.${field}`;
      frequencies[key] ??= {};
      const value = String(data[field]);
      frequencies[key][value] = (frequencies[key][value] ?? 0) + 1;
    }
  }

  console.log(JSON.stringify({
    snapshot: snapshot.rows[0].id,
    patterns: result.rows,
    frequencies,
  }, null, 2));
} finally {
  await client.end();
}
