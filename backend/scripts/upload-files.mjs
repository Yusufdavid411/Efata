import { join } from 'node:path';
import { archiveKey, readEncrypted, sha256 } from './archive.mjs';

const root = 'https://fwjxmutbsiokeevgvbat.supabase.co/storage/v1';
const bucket = 'firebase-archive';
const token = process.env.EFATA_STORAGE_ADMIN_KEY;
const id = process.argv[2] ?? '';
const dir = join('.private', 'snapshots', id);

async function storage(path, options = {}) {
  const response = await fetch(root + path, {
    ...options,
    headers: {
      apikey: token,
      ...(token.startsWith('eyJ') && { Authorization: 'Bearer ' + token }),
      ...options.headers,
    },
    redirect: 'error',
    signal: AbortSignal.timeout(90_000),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    const code = /^[A-Za-z][A-Za-z0-9_ ]{1,50}$/.test(error.error ?? '') ? ' (' + error.error + ')' : '';
    throw new Error('Supabase Storage ' + (options.method ?? 'GET') + ' HTTP ' + response.status + code);
  }
  return response;
}

async function main() {
  if (!token) throw new Error('Missing server-only Supabase Storage key');
  if (!/^\d{4}-\d{2}-\d{2}T[\d-]+Z$/.test(id)) throw new Error('Invalid snapshot ID');
  const key = archiveKey();
  const { files } = JSON.parse(await readEncrypted(join(dir, 'files.efata'), key));
  const ready = files.filter((file) => !file.error);
  if (!ready.length) {
    console.log('No files available to upload.');
    return;
  }
  const buckets = await (await storage('/bucket')).json();
  const existing = buckets.find((item) => item.id === bucket);
  if (!existing) {
    await (await storage('/bucket', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ id: bucket, name: bucket, public: false }),
    })).body?.cancel();
  } else if (existing.public !== false) {
    throw new Error('Refusing to upload private files to a public bucket');
  }
  let verified = 0;
  let failed = 0;
  for (const file of ready) {
    try {
      const bytes = await readEncrypted(join(dir, 'files', file.keyName + '.efata'), key);
      if (sha256(bytes) !== file.sha256) throw new Error('Local file checksum mismatch');
      const object = '/' + bucket + '/' + file.sha256;
      await (await storage('/object' + object, {
        method: 'POST',
        headers: { 'content-type': file.contentType ?? 'application/octet-stream', 'x-upsert': 'true' },
        body: bytes,
      })).body?.cancel();
      const result = await storage('/object/authenticated' + object);
      if (sha256(Buffer.from(await result.arrayBuffer())) !== file.sha256) {
        throw new Error('Remote file checksum mismatch');
      }
      verified++;
    } catch (error) {
      failed++;
      console.error('One private file failed: ' + error.message);
    }
  }
  console.log('Supabase Storage: ' + verified + ' files verified, ' + failed +
    ' upload/verification failures, ' + (files.length - ready.length) + ' unavailable at source.');
  if (failed || ready.length !== files.length) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
