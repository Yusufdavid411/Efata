import pg from 'pg';
import { createCoreRepository } from '../lib/core-repository.mjs';

if (!process.env.EFATA_DATABASE_URL) throw new Error('Missing EFATA_DATABASE_URL');
const ssl = {
  rejectUnauthorized: true,
  ...(process.env.EFATA_DB_CA_PEM && { ca: process.env.EFATA_DB_CA_PEM }),
};
const client = new pg.Client({ connectionString: process.env.EFATA_DATABASE_URL, ssl });
const repository = createCoreRepository({
  url: process.env.EFATA_DATABASE_URL,
  ca: process.env.EFATA_DB_CA_PEM,
});
await client.connect();
try {
  const sample = await client.query(`
    select a.firebase_uid from efata.accounts a
    left join efata.customer_profiles cp on cp.account_id = a.id
    left join efata.driver_profiles dp on dp.account_id = a.id
    where a.account_status = 'active'
      and (cp.account_id is not null or dp.account_id is not null or a.role = 'admin')
    order by a.created_at limit 1
  `);
  if (!sample.rowCount) throw new Error('No active EFATA account is available');
  const account = await repository.getMe(sample.rows[0].firebase_uid);
  const orders = await repository.listOrders({
    uid: sample.rows[0].firebase_uid, scope: 'mine', page: 1, limit: 2,
  });
  console.log(JSON.stringify({
    accountLoaded: Boolean(account?.uid),
    role: account?.role,
    profileLoaded: Boolean(account?.customerProfile || account?.driverProfile || account?.role === 'admin'),
    ordersLoaded: orders.orders.length,
  }, null, 2));
} finally {
  await client.end();
  await repository.close();
}
