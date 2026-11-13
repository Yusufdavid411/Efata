# EFATA account and dashboard rollout

1. Verify email registration, confirmation links, sign-in, refresh, logout, password changes, and recovery. Verify the admin console rejects non-admin accounts.
2. Verify customer profile editing and driver onboarding with an uploaded license, admin approval, and the online toggle.
3. Run a customer-to-driver trip: create, accept, start, complete, then check both histories and the admin Orders view. Validate payment and dispute actions separately.
4. Test chat in both directions, unread counts, and no replay after logout or trip completion. Local polling covers a running app; add a separately verified background delivery mechanism if required.
5. Test Google Maps, pickup and drop-off selection, routes, rerouting, voice navigation, and driver tracking on two Android devices.
6. Run the full regression checks and produce a signed release only after the above passes.
