# EFATA Auth, Dashboard, And Menu Upgrade

## Email OTP Registration

Registration now expects Firebase Cloud Functions to send and verify EFATA email codes. The app calls:

- `sendRegistrationCode`
- `verifyRegistrationCode`
- `completeRegistration`

The code is not generated or displayed inside Flutter. OTP values are stored only by the backend as hashes in `registrationOtps`, and Firestore rules deny all direct client reads and writes to that collection.

## Required Backend Secrets

Set these before deploying Functions:

- `RESEND_API_KEY`: email sender API key.
- `OTP_HASH_SECRET`: long random secret used to hash OTP codes.

Set this Functions parameter for the sender identity:

- `EFATA_EMAIL_FROM`: for example `EFATA <noreply@efata.app>`.

For early testing, Resend can send from `EFATA <onboarding@resend.dev>` only to verified Resend test recipients. Production needs a verified EFATA sending domain.

## Google Sign-In

Android reads `GOOGLE_WEB_CLIENT_ID` from `android/local.properties`, Gradle properties, or environment variables. Add the Firebase Web Client ID there before building an APK:

```properties
GOOGLE_WEB_CLIENT_ID=your-firebase-web-client-id.apps.googleusercontent.com
```

Google registration is available from the customer and driver registration flows. New Google users go directly to role-specific onboarding. Existing password users can connect Google from Settings if the selected Google email matches the signed-in EFATA email.

Google-created users who later want password login can use Settings to receive a secure password setup email.

## Password Policy

EFATA uses a modern passphrase-friendly policy:

- Minimum 12 characters.
- 15+ characters recommended.
- Spaces and symbols are allowed.
- Password cannot be only letters or only numbers.
- Password cannot contain EFATA, common weak words, repeated patterns, or the email name.
- Confirmation must match before account creation.

## Dashboards And Menu

Driver dashboard now uses a wallet-style earnings summary with total balance, this-month earnings, completed jobs, and payout action. Customer dashboard now shows a delivery command center with active, pending, completed, and review counts.

The drawer menu now has a richer account header, role badge, profile status, clearer role-specific actions, support/settings entries, and role-aware logout copy.

## Deploy Notes

Deploy from `C:\Users\David\Desktop\Codes\Logistics App_Project\EFATA ADMIN` after secrets are set:

```powershell
firebase.cmd functions:secrets:set RESEND_API_KEY --project logistics-app-7f9ff
firebase.cmd functions:secrets:set OTP_HASH_SECRET --project logistics-app-7f9ff
firebase.cmd deploy --only functions,firestore:rules --project logistics-app-7f9ff
```

Note: `EFATA_EMAIL_FROM` is implemented as a Firebase Functions v2 parameter. If the CLI prompts for it during deploy, enter the verified sender address. For local/deploy defaults, add `EFATA_EMAIL_FROM=EFATA <noreply@efata.app>` to `EFATA ADMIN/functions/.env`; do not commit that file.
