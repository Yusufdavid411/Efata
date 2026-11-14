# EFATA API

The Android app and admin dashboard use https://api.efata.io. Authentication is handled through the API with Supabase Auth. Application records live in the private EFATA PostgreSQL schema.

Configure the server using .env.example, apply the SQL migrations in order, and run npm test. For local API development, run npm start. Provision administrator roles only through a trusted database operator, never through public registration.

## EFATA registration email

Set up custom SMTP in Supabase Auth with a verified EFATA sender (for example,
`EFATA <accounts@efata.io>`). Disable click tracking for confirmation email.
Set Confirm signup's subject to **Welcome to EFATA: confirm your email** and
use the HTML in `supabase/confirm-signup.html`. Keep email confirmation enabled.
The link opens the backend confirmation page; tapping Confirm exchanges the
token without signing the browser in. The Android app handles `efata://login`.

Set `EFATA_RESEND_API_KEY` and `EFATA_EMAIL_FROM` as production backend
environment variables for driver review receipts and approvals. These are
best-effort emails; dispatch failures do not undo the review state change.
Apply `20261114000100_driver_vehicle_photo.sql` before accepting vehicle uploads.
