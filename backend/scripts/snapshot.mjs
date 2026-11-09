import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { archiveKey, canonicalJson, sha256, writeEncrypted } from './archive.mjs';
import { cloudinaryReferences, firebaseSource, request } from './firebase-source.mjs';

const project = 'logistics-app-7f9ff';
const maxFile = 50_000_000;
const maxTotal = 900_000_000;
const infrastructureBucket = /^(?:gcf-(?:v2-)?(?:sources|uploads)-|[a-z0-9-]+\.cloudbuild\.google\.com$|artifacts\.)/;

async function mapLimited(items, worker) {
  const output = [];
  let i = 0;
  await Promise.all(Array.from({ length: 8 }, async () => {
    while (i < items.length) {
      const index = i++;
      output[index] = await worker(items[index]);
    }
  }));
  return output;
}

async function snapshot() {
  const token = process.env.EFATA_GOOGLE_ACCESS_TOKEN;
  if (!token) throw new Error('Missing Google migration access token');
  const key = archiveKey();
  const now = new Date();
  const readTime = new Date(now.getTime() - 5000).toISOString();
  const dir = join('.private', 'snapshots', now.toISOString().replace(/[:.]/g, '-'));
  await mkdir(join(dir, 'files'), { recursive: true });
  const source = firebaseSource({ project, token });
  const report = { project, readTime, firestore: {}, auth: {}, storage: {} };
  const refs = new Set();
  const tasks = [
    async () => {
      const databases = await source.databases();
      if (databases.length === 0) throw new Error('No Firestore database was found');
      const records = [];
      for (const { name } of databases) {
        for await (const { path, document } of source.documents(name, readTime)) {
          const db = name.split('/').at(-1);
          records.push({ database: db, path, document, sha256: sha256(canonicalJson(document)) });
          const group = db + '/' + path.split('/').filter((_, i) => i % 2 === 0).join('/');
          report.firestore[group] = (report.firestore[group] ?? 0) + 1;
          cloudinaryReferences(document, refs);
        }
      }
      await writeEncrypted(join(dir, 'firestore.efata'), JSON.stringify(records), key);
      console.log('Firestore documents backed up: ' + records.length);
    },
    async () => {
      const accounts = [];
      for await (const account of source.accounts()) {
        accounts.push(account);
        cloudinaryReferences(account.photoUrl, refs);
      }
      await writeEncrypted(join(dir, 'auth.efata'), JSON.stringify(accounts), key);
      report.auth.accounts = accounts.length;
      report.auth.hashesPresent = accounts.filter((x) => x.passwordHash && x.salt).length;
      report.auth.googleAccounts = accounts.filter((x) =>
        x.providerUserInfo?.some((p) => p.providerId === 'google.com')).length;
      console.log('Firebase Auth accounts backed up: ' + accounts.length);
    },
  ];
  const results = await Promise.allSettled(tasks.map((task) => task()));
  report.sourceErrors = results.filter((x) => x.status === 'rejected').map((x) => x.reason.message);
  let copiedBytes = 0;
  const saveFile = async (record, download) => {
    try {
      if (Number(record.metadata?.size) > maxFile) throw new Error('above Free per-file limit');
      const response = await download();
      if (Number(response.headers.get('content-length')) > maxFile) {
        await response.body.cancel();
        throw new Error('above Free per-file limit');
      }
      const chunks = [];
      let length = 0;
      for await (const chunk of response.body) {
        length += chunk.length;
        if (length > maxFile) throw new Error('above Free per-file limit');
        chunks.push(chunk);
      }
      if (record.metadata?.size !== undefined && Number(record.metadata.size) !== length) {
        throw new Error('source size mismatch');
      }
      if (copiedBytes + length > maxTotal) throw new Error('above Free storage budget');
      copiedBytes += length;
      const bytes = Buffer.concat(chunks);
      const digest = sha256(bytes);
      const keyName = sha256(record.id);
      await writeEncrypted(join(dir, 'files', keyName + '.efata'), bytes, key);
      return { ...record, keyName, bytes: length, sha256: digest, contentType: response.headers.get('content-type') };
    } catch (error) {
      return { ...record, error: error.message };
    }
  };
  const files = [];
  const skippedBuckets = [];
  try {
    for await (const bucket of source.buckets()) {
      if (infrastructureBucket.test(bucket.name)) {
        skippedBuckets.push(bucket.name);
        continue;
      }
      const objects = [];
      for await (const object of source.objects(bucket.name)) objects.push(object);
      files.push(...await mapLimited(objects, (object) => saveFile({
        id: 'gs://' + object.bucket + '/' + object.name + '#' + object.generation,
        source: 'gcs',
        metadata: object,
      }, () => source.object(object))));
    }
  } catch (error) {
    report.sourceErrors.push(error.message);
  }
  files.push(...await mapLimited([...refs], (id) => saveFile({ id, source: 'cloudinary' },
    () => request(id, { label: 'Cloudinary file' }))));
  await writeEncrypted(join(dir, 'files.efata'), JSON.stringify({ files, skippedBuckets }), key);
  report.storage = {
    discovered: files.length,
    downloaded: files.filter((x) => !x.error).length,
    failed: files.filter((x) => x.error).length,
    bytes: copiedBytes,
    skippedInfrastructureBuckets: skippedBuckets.length,
    failures: Object.entries(Object.groupBy(files.filter((x) => x.error), (x) => x.error))
      .map(([reason, entries]) => ({ reason, count: entries.length })),
  };
  await writeEncrypted(join(dir, 'report.efata'), JSON.stringify(report), key);
  console.log(JSON.stringify({ dir, ...report }, null, 2));
  if (report.sourceErrors.length || report.storage.failed) process.exitCode = 1;
}

snapshot().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
