create schema if not exists efata_migration;
revoke all on schema efata_migration from public, anon, authenticated, service_role;

create table if not exists efata_migration.snapshots (
  id text primary key,
  firebase_project text not null check (firebase_project = 'logistics-app-7f9ff'),
  read_time timestamptz not null,
  imported_at timestamptz not null default now(),
  report jsonb not null
);

create table if not exists efata_migration.firestore_documents (
  snapshot_id text not null references efata_migration.snapshots(id),
  database_id text not null,
  document_path text not null,
  document jsonb not null,
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  primary key (snapshot_id, database_id, document_path)
);

create table if not exists efata_migration.firebase_accounts (
  snapshot_id text not null references efata_migration.snapshots(id),
  firebase_uid text not null,
  account_metadata jsonb not null,
  primary key (snapshot_id, firebase_uid)
);

create table if not exists efata_migration.source_files (
  snapshot_id text not null references efata_migration.snapshots(id),
  source_id text not null,
  record jsonb not null,
  primary key (snapshot_id, source_id)
);

revoke all on all tables in schema efata_migration from public, anon, authenticated, service_role;
alter table efata_migration.snapshots enable row level security;
alter table efata_migration.firestore_documents enable row level security;
alter table efata_migration.firebase_accounts enable row level security;
alter table efata_migration.source_files enable row level security;
