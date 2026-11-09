# EFATA backend migration

Source: Firebase project `logistics-app-7f9ff`. Destination: EFATA's separate
Supabase project `fwjxmutbsiokeevgvbat`. The production Flutter app and admin
dashboard are unchanged. This repository is the migration tooling and backend
health endpoint, not a production cutover.

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

## Backend hosting

Use this directory as the Vercel project root, with Node 24.
`GET /api/live` checks that the runtime starts without needing credentials.
`GET /api/health` separately checks database readiness and returns 503 without
a database connection. For an isolated hosting test, ship only `api/` and the
package manifests, with no database credentials or backups.

To enable database readiness, configure `EFATA_READ_DATABASE_URL` on the server
with a restricted Postgres role and `EFATA_DB_CA_PEM` if needed; do not use the
migration owner password. Omit SSL parameters in the URL so the explicit TLS
settings are used. Run
`npm start` for the local health endpoint. No client data is exposed here.
Deploy only under the new EFATA Vercel scope, not the existing personal scope.
