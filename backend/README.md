# EFATA backend migration

Source: Firebase project `logistics-app-7f9ff`. Destination: EFATA's separate
Supabase project `fwjxmutbsiokeevgvbat`. The production Flutter app and admin
dashboard are unchanged. This repository contains the migration tools, health
checks, and an opt-in order history preview, not a production cutover.

## Snapshot and verification

1. Run `npm ci` and `npm test` on Node 24. Install the Google Cloud and Supabase
   CLIs and sign in with the appropriate project accounts.
2. Link the **EFATA** Supabase project, then apply the SQL with
   `supabase db push --linked`. Never link the unrelated project.
3. On the provisioning Windows account, run
   `./scripts/run-private.ps1 snapshot`. If needed, set
   `EFATA_GCLOUD_PATH` to the local `gcloud.cmd`.
4. Run `./scripts/run-private.ps1 import <snapshot-directory-name>`. It imports
   Firestore wire-format documents at their original paths, Auth account
   metadata under the original Firebase IDs, and a file inventory. The
   transaction commits only after source/destination verification. A partial
   storage inventory is recorded, not silently accepted as a complete move.
   Download the project's Supabase Postgres CA certificate to
   `.private/supabase-ca.crt` if the client does not already trust that CA.
5. With a server-only `EFATA_STORAGE_ADMIN_KEY` in the local environment, run
   `./scripts/run-private.ps1 files <snapshot-directory-name>`. Available files
   are copied to a private bucket and downloaded again to verify their SHA-256.
   Missing or oversized files must be resolved before switching app file URLs.

Snapshots and migration credentials live in ignored `.private/`. Snapshots use
authenticated encryption; key and database password files use Windows DPAPI.
The Windows account and its recovery setup are required to decrypt them. Make
a separately secured recovery copy of the key before relying on these backups.
Do not upload backups, credentials, or hash parameters to GitHub or Vercel.
The archive traverses nested and orphaned Firestore collections and uses one
Firestore read timestamp. Auth and file reads are separate, and the copy is
not a substitute for a final reconciliation of writes during cutover.

## Application cutover gates

- Preserve Firebase UIDs in the relational schema and map them explicitly to
  any eventual Supabase Auth IDs. Existing Firebase sign-in can remain live
  while the new data API is tested. For fully replacing Firebase Auth, verify
  legacy passwords and rehash on successful sign-in, and link Google identities
  only after validating provider identity. Do not treat copied metadata as
  native Supabase login accounts or old profile role fields as trusted grants.
- Port and test mobile and admin reads/writes, order transitions, chat and
  unread receipts, live tracking, payout and admin access, registration email,
  and private file access. Test existing customer and driver accounts on-device.
- Reconcile source and destination again before switching, keep Firebase
  available for rollback, and retire it only after the app is verified.
- The Cloudinary copy covers app-referenced URLs, not an account-wide asset
  inventory. Audit the Cloudinary Media Library before retiring that account.

## Test the client connection

The order history preview uses a fixed Supabase snapshot, not current delivery
status. It keeps existing sign-in during testing and validates the Firebase
session with Google. The API returns order summaries only. The preview does not
create orders, change delivery status, open live tracking, or modify Firestore.

1. Apply the Supabase migrations. Provision a server-only password for
   `efata_preview_reader`, enable LOGIN on that role, and use its pooler URL in
   `EFATA_PREVIEW_DATABASE_URL`. It can read only the two preview views, not the
   underlying archive. Use the Supabase database CA for TLS verification.
2. Set `EFATA_ORDER_PREVIEW=1`, the verified `EFATA_PREVIEW_SNAPSHOT_ID`, and
   `EFATA_FIREBASE_LOOKUP_API_KEY` (a Firebase client API key authorized for
   Identity Toolkit). Set `EFATA_PREVIEW_ORIGINS` to the exact admin origin and
   `EFATA_PREVIEW_ADMIN_UIDS` to independently verified admin IDs. Never populate
   the allowlist from the archived Firestore roles.
3. Start the loopback API with `npm start` (default port 3000). On the
   provisioning laptop, `./scripts/start-order-preview.ps1 -SnapshotId <id>`
   sets the database connection from the protected local reader credential.
   On the Admin
   preview branch set `VITE_EFATA_API_ORIGIN=http://127.0.0.1:3000`, start Vite, and
   open **Order History Preview** after sign-in.
4. On the Flutter preview branch, use a debug build with
   `--dart-define=EFATA_API_ORIGIN=http://10.0.2.2:3000` for an Android emulator.
   For an attached phone, run `adb reverse tcp:3000 tcp:3000` and use
   `http://127.0.0.1:3000` instead. Sign in and open **My Orders** or **Job
   History**. Do not include the define in production builds before cutover.

## Custom domains and Firebase retirement

- Keep the live website at `https://www.efata.io`. Reserve
  `https://admin.efata.io` for the dashboard and `https://api.efata.io` for the
  API. Both clients should use `https://api.efata.io` as their API origin.
  Allow `https://admin.efata.io` in the API's CORS settings. Only public API
  URLs go in client builds.
- Add each hostname to its corresponding deployed project and use the exact
  DNS records shown for that hostname. Do not change the apex, www, or mail
  records as part of the subdomain setup. Verify certificates, CORS, auth
  callbacks, and access controls before changing live client settings. Do not
  overwrite an existing live DNS record until its replacement is verified.
- Retire Firebase only after native authentication, deliveries, chats,
  notifications, payouts, admin actions, and file access are tested end to end.
  Prevent old versions from writing during cutover, reconcile the final delta,
  and verify real app and admin traffic on the new services. Keep the encrypted
  backup and the old services available during the agreed rollback window. Do
  not delete the Firebase project as part of switching clients.

## Backend hosting

Use this directory as the Vercel project root, with Node 24. The live EFATA
endpoint is `https://api.efata.io`; the root path and `GET /api/live` both
return a credential-free liveness response.
`GET /api/health` separately checks database readiness and returns 503 without
a database connection. For an isolated hosting test, ship only `api/`,
`lib/`, and the package manifests, with no database credentials or backups.

To enable database readiness, configure `EFATA_READ_DATABASE_URL` on the server
with a restricted Postgres role and `EFATA_DB_CA_PEM` if needed; do not use the
migration owner password. Omit SSL parameters in the URL so the explicit TLS
settings are used. Run `npm start` for the local API. Client data is not
available unless the order preview is explicitly enabled and authenticated.
Deploy only under the new EFATA Vercel scope, not the existing personal scope.

The production API uses two different database logins. `efata_health_reader`
can connect and run the readiness probe but has no EFATA table privileges.
`efata_api_runtime` can access only the private `efata` schema and is used by
feature endpoints through `EFATA_DATABASE_URL`. Neither login may be placed in
Flutter, Vite variables, GitHub, or documentation. Run
`scripts/provision-runtime.ps1` from a trusted Windows account to rotate both
passwords and save them in ignored, DPAPI-protected files.

## Materializing the Firebase archive

`npm run audit:archive` reports collection shapes and enum frequencies without
printing customer data. `npm run materialize:core` performs a read-only dry run.
Run `node scripts/materialize-core.mjs --apply` only through the private owner
password wrapper after reviewing that plan. The importer is transactional,
records the snapshot in `efata.migration_runs`, preserves decoded source
documents in `legacy_data`, and refuses to apply the same snapshot twice.
