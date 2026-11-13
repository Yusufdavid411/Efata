import { createCoreRepository } from './core-repository.mjs';
import { createSupabaseVerifier } from './supabase-auth.mjs';

export function createRuntime(env = process.env) {
  if (!env.EFATA_DATABASE_URL || !env.EFATA_SUPABASE_URL ||
      !env.EFATA_SUPABASE_PUBLIC_KEY) return null;
  const repository = createCoreRepository({ url: env.EFATA_DATABASE_URL, ca: env.EFATA_DB_CA_PEM });
  return {
    verifyRegistration: createSupabaseVerifier({
      url: env.EFATA_SUPABASE_URL, key: env.EFATA_SUPABASE_PUBLIC_KEY,
    }),
    verify: createSupabaseVerifier({
      url: env.EFATA_SUPABASE_URL,
      key: env.EFATA_SUPABASE_PUBLIC_KEY,
      findIdentity: repository.findSupabaseIdentity,
    }),
    repository,
  };
}
