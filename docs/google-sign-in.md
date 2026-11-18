# Google sign-in

Android uses the official Google account chooser via `google_sign_in`. The ID
token is sent only over HTTPS to EFATA `/api/auth` with action `google`.
The backend delegates token verification to the configured Google provider and
returns the same session format used by email sign-in. No client secret belongs
in the APK. Supabase remains the server-side identity provider.

The existing browser OAuth flow is retained as a PKCE fallback when native
client configuration is unavailable. It also requests account selection. Both
flows exchange credentials through EFATA's API and share the same bootstrap path.

Build with `--dart-define=GOOGLE_SIGN_IN_WEB_CLIENT_ID=<web-client-id>`.
The ID must appear in the production Google provider's accepted client IDs.
Keep the existing first client ID and its secret when adding a native audience.
Register `com.efata.logistics` plus its actual signing SHA-1 in an Android OAuth
client in the same Google Cloud project as the build's web client ID. A release
certificate must be registered separately if different from debug signing.

Existing EFATA accounts retain their role and records. For a new Google identity,
the bootstrap endpoint requires Passenger or Driver selection. Google verifies
email ownership; email confirmation and a password are not required in this flow.
Provider identity linking is handled by Supabase's verified-email linking rules;
the application must not merge database accounts solely by a client-supplied email.
Unfinished profiles enter onboarding; completed profiles enter their dashboard.
Canceled Google selection does not display a failure notification.

Verify on a signed Android build: chooser opens, cancellation is quiet, existing
accounts retain records, new accounts pick a role once, and email/password login
still works. Google sign-in alone does not set a password on a Google-only account.
