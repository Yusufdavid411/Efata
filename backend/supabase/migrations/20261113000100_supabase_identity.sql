alter table efata.accounts add column supabase_auth_id uuid unique
  references auth.users(id) on delete set null;
