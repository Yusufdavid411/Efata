import { join } from 'node:path';
import { archiveKey, readEncrypted, writeEncrypted } from './archive.mjs';
import { cloudinaryReferences, firebaseSource } from './firebase-source.mjs';

async function main() {
  const id = process.argv[2] ?? '';
  if (!/^\d{4}-\d{2}-\d{2}T[\d-]+Z$/.test(id)) throw new Error('Invalid snapshot ID');
  const dir = join('.private', 'snapshots', id);
  const key = archiveKey();
  const project = 'logistics-app-7f9ff';
  const token = process.env.EFATA_GOOGLE_ACCESS_TOKEN;
  const original = JSON.parse(await readEncrypted(join(dir, 'report.efata'), key));
  if (!token || original.project !== project ||
      !original.sourceErrors.some((error) => error.startsWith('Firebase Auth accounts:'))) {
    throw new Error('Snapshot does not require Auth recovery');
  }
  const accounts = await Array.fromAsync(firebaseSource({ project, token }).accounts());
  const { files } = JSON.parse(await readEncrypted(join(dir, 'files.efata'), key));
  const refs = new Set(files.map((file) => file.id));
  const extra = new Set(accounts.flatMap((account) =>
    [...cloudinaryReferences(account.photoUrl), ...cloudinaryReferences(account.providerUserInfo)]).filter((url) => !refs.has(url)));
  const report = {
    accounts: accounts.length,
    hashesPresent: accounts.filter((account) => account.passwordHash && account.salt).length,
    googleAccounts: accounts.filter((account) => account.providerUserInfo?.some((p) => p.providerId === 'google.com')).length,
    additionalCloudinaryReferences: extra.size,
    capturedAt: new Date().toISOString(),
  };
  await writeEncrypted(join(dir, 'auth.efata'), JSON.stringify(accounts), key);
  await writeEncrypted(join(dir, 'auth-recovery.efata'), JSON.stringify(report), key);
  console.log(JSON.stringify(report));
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
