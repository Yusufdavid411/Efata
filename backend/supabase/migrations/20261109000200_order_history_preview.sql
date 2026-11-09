create role efata_preview_reader nologin;
create schema efata_preview;
revoke all on schema efata_preview from public, anon, authenticated, service_role;

create view efata_preview.snapshot_info as
select id, read_time from efata_migration.snapshots
where firebase_project = 'logistics-app-7f9ff';

create view efata_preview.order_summaries as
select
  doc.snapshot_id,
  split_part(doc.document_path, '/', 2) as order_id,
  doc.document #>> '{fields,customerId,stringValue}' as customer_id,
  doc.document #>> '{fields,driverId,stringValue}' as driver_id,
  doc.document #>> '{fields,pickup,stringValue}' as pickup,
  doc.document #>> '{fields,dropoff,stringValue}' as dropoff,
  doc.document #>> '{fields,vehicleType,stringValue}' as vehicle_type,
  doc.document #>> '{fields,status,stringValue}' as status,
  coalesce(
    doc.document #>> '{fields,createdAt,timestampValue}',
    doc.document ->> 'createTime'
  )::timestamptz as created_at
from efata_migration.firestore_documents doc
join efata_preview.snapshot_info snapshot on snapshot.id = doc.snapshot_id
where doc.database_id = '(default)' and doc.document_path ~ '^orders/[^/]+$';

revoke all on all tables in schema efata_preview from public, anon, authenticated, service_role;
grant usage on schema efata_preview to efata_preview_reader;
grant select on efata_preview.snapshot_info, efata_preview.order_summaries to efata_preview_reader;
