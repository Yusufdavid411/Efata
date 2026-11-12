alter table efata.driver_profiles
  drop constraint if exists driver_profiles_verification_status_check;
alter table efata.driver_profiles
  add constraint driver_profiles_verification_status_check
  check (verification_status in ('pending', 'incomplete', 'approved', 'rejected', 'suspended'));

alter table efata.orders
  add column if not exists dispute_status text not null default 'none',
  add column if not exists dispute_note text,
  add column if not exists dispute_updated_at timestamptz,
  add column if not exists payment_review_required boolean not null default false;
alter table efata.orders
  drop constraint if exists orders_dispute_status_check;
alter table efata.orders
  add constraint orders_dispute_status_check
  check (dispute_status in ('none', 'open', 'resolved'));

alter table efata.payouts
  drop constraint if exists payouts_status_check;
alter table efata.payouts
  add constraint payouts_status_check
  check (status in ('pending', 'ready', 'review', 'approved', 'held', 'processing', 'paid', 'rejected'));

grant select, insert, update, delete on all tables in schema efata to efata_api_runtime;
