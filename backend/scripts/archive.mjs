import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';

const header = Buffer.from('EFATA-1\n');

export function archiveKey(env = process.env) {
  const hex = env.EFATA_ARCHIVE_KEY ?? '';
  if (!/^[a-f0-9]{64}$/i.test(hex)) throw new Error('Missing encrypted-backup key');
  return Buffer.from(hex, 'hex');
}

export function seal(bytes, key) {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(header);
  const payload = Buffer.concat([cipher.update(bytes), cipher.final()]);
  return Buffer.concat([header, nonce, cipher.getAuthTag(), payload]);
}

export function unseal(file, key) {
  if (file.length < header.length + 28 || !file.subarray(0, header.length).equals(header)) {
    throw new Error('Invalid encrypted-backup format');
  }
  const start = header.length;
  const decipher = createDecipheriv('aes-256-gcm', key, file.subarray(start, start + 12));
  decipher.setAAD(header);
  decipher.setAuthTag(file.subarray(start + 12, start + 28));
  return Buffer.concat([decipher.update(file.subarray(start + 28)), decipher.final()]);
}

export async function writeEncrypted(file, bytes, key) {
  await writeFile(file, seal(bytes, key), { flag: 'wx', mode: 0o600 });
}

export async function readEncrypted(file, key) {
  return unseal(await readFile(file), key);
}

export function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

export function canonicalJson(value) {
  if (Array.isArray(value)) return '[' + value.map(canonicalJson).join(',') + ']';
  if (value && typeof value === 'object') {
    return '{' + Object.keys(value).sort().map(
      (key) => JSON.stringify(key) + ':' + canonicalJson(value[key]),
    ).join(',') + '}';
  }
  return JSON.stringify(value);
}
