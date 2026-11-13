import { createCoreRepository } from './core-repository.mjs';
import { createPreviewVerifier } from './preview-auth.mjs';
import { createSupabaseVerifier } from './supabase-auth.mjs';

export function createRuntime(env = process.env) {
  const useSupabase = env.EFATA_AUTH_PROVIDER === 'supabase';
  if (!env.EFATA_DATABASE_URL || (useSupabase
    ? !env.EFATA_SUPABASE_URL || !env.EFATA_SUPABASE_PUBLIC_KEY
    : !env.EFATA_FIREBASE_LOOKUP_API_KEY)) return null;
  const repository = createCoreRepository({ url: env.EFATA_DATABASE_URL, ca: env.EFATA_DB_CA_PEM });
  return {
    verify: useSupabase ? createSupabaseVerifier({
      url: env.EFATA_SUPABASE_URL,
      key: env.EFATA_SUPABASE_PUBLIC_KEY,
      findIdentity: repository.findSupabaseIdentity,
    }) : createPreviewVerifier({ apiKey: env.EFATA_FIREBASE_LOOKUP_API_KEY }),
    repository,
  };
}
