alter table efata.admin_logs
  add column if not exists firebase_log_id text;
create unique index if not exists admin_logs_firebase_id_unique
  on efata.admin_logs (firebase_log_id) where firebase_log_id is not null;

create table if not exists efata.migration_runs (
  snapshot_id text primary key,
  report jsonb not null,
  applied_at timestamptz not null default now()
);

revoke all on efata.migration_runs from public, anon, authenticated, service_role;
grant select on efata.migration_runs to efata_api_runtime;
