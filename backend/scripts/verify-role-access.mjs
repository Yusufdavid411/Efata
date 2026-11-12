import pg from 'pg';

const role = process.env.EFATA_TEST_ROLE;
const expectedTableAccess = process.env.EFATA_EXPECT_TABLE_ACCESS === '1';
const client = new pg.Client({
  host: process.env.EFATA_POOLER_HOST,
  port: 6543,
  user: `${role}.${process.env.EFATA_PROJECT_REF}`,
  database: 'postgres',
  password: process.env.EFATA_TEST_PASSWORD,
  ssl: { rejectUnauthorized: true },
  connectionTimeoutMillis: 15_000,
});

await client.connect();
try {
  await client.query('select 1');
  let hasTableAccess = true;
  try {
    await client.query('select count(*) from efata.accounts');
  } catch (error) {
    if (error.code !== '42501') throw error;
    hasTableAccess = false;
  }
  if (hasTableAccess !== expectedTableAccess) {
    throw new Error(`${role} table-access boundary is incorrect`);
  }
} finally {
  await client.end();
}

