import { basename, join } from 'node:path';
import pg from 'pg';
import { archiveKey, canonicalJson, readEncrypted, sha256 } from './archive.mjs';

const project = 'logistics-app-7f9ff';
const target = 'fwjxmutbsiokeevgvbat';

export function accountMetadata(account) {
  const fields = ['localId', 'email', 'emailVerified', 'displayName', 'photoUrl',
    'phoneNumber', 'disabled', 'createdAt', 'lastLoginAt', 'validSince', 'tenantId'];
  const providerFields = ['providerId', 'rawId', 'federatedId', 'email',
    'displayName', 'photoUrl', 'phoneNumber'];
  const pick = (input, keys) => Object.fromEntries(
    keys.filter((key) => Object.hasOwn(input, key)).map((key) => [key, input[key]]),
  );
  return {
    ...pick(account, fields),
    providerUserInfo: (account.providerUserInfo ?? []).map((provider) => pick(provider, providerFields)),
  };
}

async function loadRows(client, statement, rows) {
  for (let offset = 0; offset < rows.length; offset += 25) {
    await client.query(statement, [JSON.stringify(rows.slice(offset, offset + 25))]);
  }
}

async function main() {
  const id = process.argv[2] ?? '';
  if (basename(id) !== id || !/^\d{4}-\d{2}-\d{2}T[\d-]+Z$/.test(id)) {
    throw new Error('Provide a snapshot directory name from .private/snapshots');
  }
  const key = archiveKey();
  const parse = async (name) => JSON.parse(await readEncrypted(join('.private', 'snapshots', id, name + '.efata'), key));
  const [docs, accounts, { files }, report] = await Promise.all(
    ['firestore', 'auth', 'files', 'report'].map(parse),
  );
  const authRecovery = await parse('auth-recovery').catch((error) => {
    if (error.code === 'ENOENT') return null;
    throw error;
  });
  if (authRecovery) {
    report.auth = authRecovery;
    report.sourceErrors = report.sourceErrors.filter((error) => !error.startsWith('Firebase Auth accounts:'));
  }
  if (report.project !== project || docs.length === 0 || accounts.length === 0) {
    throw new Error('Snapshot does not contain the expected Firebase data');
  }
  const pooler = new URL(process.env.EFATA_DB_POOLER_URL);
  if (pooler.username !== 'postgres.' + target || !pooler.hostname.endsWith('.pooler.supabase.com')) {
    throw new Error('The connection does not target the new EFATA project');
  }
  const password = process.env.EFATA_DB_PASSWORD;
  if (!password) throw new Error('Missing EFATA database password');
  const client = new pg.Client({
    host: pooler.hostname,
    port: Number(pooler.port || 5432),
    user: pooler.username,
    database: 'postgres',
    password,
    ssl: { rejectUnauthorized: true },
    connectionTimeoutMillis: 15_000,
  });
  await client.connect();
  try {
    await client.query('begin');
    await client.query(
      'insert into efata_migration.snapshots (id, firebase_project, read_time, report) values ($1, $2, $3, $4) on conflict do nothing',
      [id, project, report.readTime, report],
    );
    await loadRows(client, `
      insert into efata_migration.firestore_documents
      select snapshot_id, database_id, document_path, document, sha256
      from jsonb_to_recordset($1) as r(snapshot_id text, database_id text, document_path text, document jsonb, sha256 text)
      on conflict do nothing
    `, docs.map((doc) => ({
      snapshot_id: id, database_id: doc.database, document_path: doc.path, document: doc.document, sha256: doc.sha256,
    })));
    await loadRows(client, `
      insert into efata_migration.firebase_accounts
      select snapshot_id, firebase_uid, account_metadata
      from jsonb_to_recordset($1) as r(snapshot_id text, firebase_uid text, account_metadata jsonb)
      on conflict do nothing
    `, accounts.map((account) => ({
      snapshot_id: id, firebase_uid: account.localId, account_metadata: accountMetadata(account),
    })));
    await loadRows(client, `
      insert into efata_migration.source_files
      select snapshot_id, source_id, record
      from jsonb_to_recordset($1) as r(snapshot_id text, source_id text, record jsonb)
      on conflict do nothing
    `, files.map((file) => ({ snapshot_id: id, source_id: file.id, record: file })));

    const fetched = await client.query(
      'select database_id, document_path, document, sha256 from efata_migration.firestore_documents where snapshot_id = $1',
      [id],
    );
    const expected = new Map(docs.map((doc) => [doc.database + '/' + doc.path, doc.sha256]));
    if (fetched.rowCount !== docs.length || fetched.rows.some((row) => {
      const digest = expected.get(row.database_id + '/' + row.document_path);
      return digest !== row.sha256 || digest !== sha256(canonicalJson(row.document));
    })) throw new Error('Firestore checksum verification failed');

    for (const { table, keyColumn, valueColumn, source } of [
      { table: 'firebase_accounts', keyColumn: 'firebase_uid', valueColumn: 'account_metadata',
        source: new Map(accounts.map((a) => [a.localId, accountMetadata(a)])) },
      { table: 'source_files', keyColumn: 'source_id', valueColumn: 'record',
        source: new Map(files.map((f) => [f.id, f])) },
    ]) {
      const result = await client.query(
        'select ' + keyColumn + ', ' + valueColumn + ' from efata_migration.' + table + ' where snapshot_id = $1', [id],
      );
      if (result.rowCount !== source.size || result.rows.some((row) =>
        canonicalJson(source.get(row[keyColumn])) !== canonicalJson(row[valueColumn]))) {
        throw new Error(table + ' verification failed');
      }
    }
    await client.query('commit');
    console.log('Verified in EFATA Supabase: ' + docs.length + ' Firestore documents, ' +
      accounts.length + ' account metadata records, ' + files.length + ' file inventory records.');
  } catch (error) {
    await client.query('rollback');
    throw error;
  } finally {
    await client.end();
  }
}

if (process.argv[1]?.endsWith('import.mjs')) {
  main().catch((error) => {
    console.error(error.code ? 'Database import failed (' + error.code + ').' : error.message);
    process.exitCode = 1;
  });
}
