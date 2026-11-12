import { createCoreRepository } from './core-repository.mjs';
import { createPreviewVerifier } from './preview-auth.mjs';

export function createRuntime(env = process.env) {
  if (!env.EFATA_DATABASE_URL || !env.EFATA_FIREBASE_LOOKUP_API_KEY) return null;
  const repository = createCoreRepository({ url: env.EFATA_DATABASE_URL, ca: env.EFATA_DB_CA_PEM });
  return {
    verify: createPreviewVerifier({ apiKey: env.EFATA_FIREBASE_LOOKUP_API_KEY }),
    repository,
  };
}
