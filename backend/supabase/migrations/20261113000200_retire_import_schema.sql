drop schema if exists efata_preview cascade;
drop schema if exists efata_migration cascade;
drop table if exists efata.migration_runs;
alter table efata.accounts drop column if exists firebase_uid;
alter table efata.orders drop column if exists firebase_order_id;
alter table efata.order_messages drop column if exists firebase_message_id;
alter table efata.payouts drop column if exists firebase_payout_id;
alter table efata.admin_logs drop column if exists firebase_log_id;
