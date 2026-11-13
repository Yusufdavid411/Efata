create schema if not exists efata;

revoke all on schema efata from public, anon, authenticated, service_role;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'efata_health_reader') then
    create role efata_health_reader nologin nosuperuser nocreatedb nocreaterole noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'efata_api_runtime') then
    create role efata_api_runtime nologin nosuperuser nocreatedb nocreaterole noinherit;
  end if;
end
$$;

create table if not exists efata.accounts (
  id uuid primary key default gen_random_uuid(),
  email text,
  role text not null check (role in ('customer', 'driver', 'admin')),
  display_name text,
  phone text,
  photo_url text,
  email_verified boolean not null default false,
  profile_completed boolean not null default false,
  account_status text not null default 'active'
    check (account_status in ('active', 'disabled', 'pending_deletion')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  legacy_data jsonb not null default '{}'::jsonb,
  check (email is null or email = lower(email))
);

create unique index if not exists accounts_email_unique
  on efata.accounts (lower(email)) where email is not null;
create index if not exists accounts_role_idx on efata.accounts (role);

create table if not exists efata.auth_identities (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references efata.accounts(id) on delete cascade,
  provider text not null,
  provider_subject text not null,
  email text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  unique (provider, provider_subject)
);

create table if not exists efata.customer_profiles (
  account_id uuid primary key references efata.accounts(id) on delete cascade,
  default_pickup_address text,
  default_pickup_lat double precision,
  default_pickup_lng double precision,
  updated_at timestamptz not null default now()
);

create table if not exists efata.driver_profiles (
  account_id uuid primary key references efata.accounts(id) on delete cascade,
  vehicle_type text,
  plate_number text,
  license_file_key text,
  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'approved', 'rejected', 'suspended')),
  verification_notes text,
  is_online boolean not null default false,
  current_lat double precision,
  current_lng double precision,
  heading double precision,
  location_updated_at timestamptz,
  total_earnings numeric(14,2) not null default 0,
  updated_at timestamptz not null default now()
);

create index if not exists driver_profiles_online_idx
  on efata.driver_profiles (is_online, verification_status);

create table if not exists efata.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references efata.accounts(id),
  driver_id uuid references efata.accounts(id),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'inTransit', 'completed', 'canceled')),
  pickup_label text not null,
  pickup_lat double precision,
  pickup_lng double precision,
  dropoff_label text not null,
  dropoff_lat double precision,
  dropoff_lng double precision,
  item_description text,
  vehicle_type text,
  scheduled_for timestamptz,
  distance_meters integer,
  duration_seconds integer,
  amount numeric(14,2),
  payment_method text,
  payment_status text not null default 'pending',
  accepted_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  canceled_at timestamptz,
  canceled_by text,
  chat_closed_at timestamptz,
  unread_for_customer integer not null default 0 check (unread_for_customer >= 0),
  unread_for_driver integer not null default 0 check (unread_for_driver >= 0),
  last_message text,
  last_message_at timestamptz,
  last_message_sender_id uuid references efata.accounts(id),
  notification_status text,
  needs_admin_review boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  legacy_data jsonb not null default '{}'::jsonb
);

create index if not exists orders_customer_created_idx
  on efata.orders (customer_id, created_at desc);
create index if not exists orders_driver_created_idx
  on efata.orders (driver_id, created_at desc);
create index if not exists orders_available_idx
  on efata.orders (created_at desc) where status = 'pending' and driver_id is null;
create unique index if not exists orders_one_active_per_driver
  on efata.orders (driver_id)
  where driver_id is not null and status in ('accepted', 'inTransit');

create table if not exists efata.order_messages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references efata.orders(id) on delete cascade,
  sender_id uuid not null references efata.accounts(id),
  sender_role text not null check (sender_role in ('customer', 'driver', 'admin')),
  body text not null check (length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index if not exists order_messages_order_created_idx
  on efata.order_messages (order_id, created_at);

create table if not exists efata.chat_notification_receipts (
  account_id uuid not null references efata.accounts(id) on delete cascade,
  order_id uuid not null references efata.orders(id) on delete cascade,
  message_time bigint not null check (message_time > 0),
  delivered_at timestamptz not null default now(),
  primary key (account_id, order_id, message_time)
);

create table if not exists efata.payouts (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references efata.accounts(id),
  amount numeric(14,2) not null check (amount > 0),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'processing', 'paid', 'rejected')),
  bank_reference text,
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists efata.admin_logs (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references efata.accounts(id),
  action text not null,
  target_type text,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists efata.file_assets (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references efata.accounts(id),
  purpose text not null,
  storage_bucket text not null,
  storage_key text not null,
  content_type text,
  size_bytes bigint,
  sha256 text,
  created_at timestamptz not null default now(),
  unique (storage_bucket, storage_key)
);

create or replace function efata.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, efata
as $$
begin
  new.updated_at = now();
  return new;
end
$$;

drop trigger if exists accounts_set_updated_at on efata.accounts;
create trigger accounts_set_updated_at before update on efata.accounts
for each row execute function efata.set_updated_at();
drop trigger if exists customer_profiles_set_updated_at on efata.customer_profiles;
create trigger customer_profiles_set_updated_at before update on efata.customer_profiles
for each row execute function efata.set_updated_at();
drop trigger if exists driver_profiles_set_updated_at on efata.driver_profiles;
create trigger driver_profiles_set_updated_at before update on efata.driver_profiles
for each row execute function efata.set_updated_at();
drop trigger if exists orders_set_updated_at on efata.orders;
create trigger orders_set_updated_at before update on efata.orders
for each row execute function efata.set_updated_at();

revoke all on all tables in schema efata from public, anon, authenticated, service_role;
revoke all on all sequences in schema efata from public, anon, authenticated, service_role;
revoke all on all functions in schema efata from public, anon, authenticated, service_role;

grant connect on database postgres to efata_health_reader, efata_api_runtime;
grant usage on schema efata to efata_api_runtime;
grant select, insert, update, delete on all tables in schema efata to efata_api_runtime;
grant usage, select on all sequences in schema efata to efata_api_runtime;
grant execute on function efata.set_updated_at() to efata_api_runtime;

alter default privileges in schema efata revoke all on tables from public, anon, authenticated, service_role;
alter default privileges in schema efata revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges in schema efata revoke all on functions from public, anon, authenticated, service_role;
alter default privileges in schema efata grant select, insert, update, delete on tables to efata_api_runtime;
alter default privileges in schema efata grant usage, select on sequences to efata_api_runtime;

