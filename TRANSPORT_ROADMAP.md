# EFATA transport roadmap

The reference app is useful for deciding what belongs on the first screen. EFATA should keep its existing bottom navigation and surface actions only when they are available.

## 1. Driver home and existing deliveries

- Lead with the map and online status. Center on a fresh device fix when going online; do not display a live location when offline. Keep active and available jobs nearby and move earnings behind a secondary action.
- Keep Jobs and Profile in the bottom navigation. Put trip-specific support, privacy and any future driver portal under Profile or the relevant job rather than adding permanent home controls.
- Give Send its own customer entry point. Add optional goods photos with private access for order participants and operations staff. Add motorbike for small parcels only after defining eligible cargo, vehicle capacity and driver matching.
- Show pickup and delivery estimates separately from actual timestamps; label estimates and show when unavailable.

## 2. Booking and dispatch

- Distinguish Send goods, Book a ride, Schedule a ride, and Intercity seats. Do not present unfinished services as bookable.
- Define separate passenger and parcel categories, availability, capacity and quotes. Priority can search more eligible classes if the passenger agrees to the price range; do not promise a faster match.
- Define a server-owned scheduled booking lifecycle, assignment window, driver acceptance and cancellation. If a driver withdraws, reopen the request or let the passenger rebook without double charges.
- Quote a base fare plus distance and estimated time by service. Define a disclosed wait-time grace period and rate, measured from a verified arrival event. Keep an audit trail and dispute route before charging wait fees.

## 3. Accounts, communication and payments

- Keep branded transactional email. Restore Google sign-in and signup through the existing auth backend; preserve account identity and role on repeat sign-ins.
- Add an admin announcements inbox with driver/customer targeting, preview and audit history. Keep optional promotional messages separate from operational notices and delivery chat.
- Add private in-app voice calls for active job participants with ringing, mute and end controls, and a clear fallback when unavailable. Choose the voice provider and test weak-network behavior before release.
- Keep cash where supported. Evaluate hosted card checkout first; add saved cards only using provider tokens and verified callbacks, never storing card numbers or CVVs. Treat funded balances as a separate project with a reconciled ledger, refund rules and a compliance review before launch.

## 4. Intercity merchant pilot

- Start with a small set of verified operators on one route, such as Lokoja to Abuja. Merchants manage departure time, boarding point, fare, capacity and seat inventory.
- Hold seats temporarily during checkout, then confirm only after payment verification. Support one or more seats initially; whole-vehicle and custom-departure requests should have explicit terms. Define missed departures, refunds, cancellations, operator messaging and settlement with pilot partners.

## 5. Driver trust and incentives

- Selfie checks are feasible, but a camera capture alone does not establish identity. Evaluate consent, private storage, retention, liveness and a manual review path before introducing them; do not block drivers automatically in the first pilot.
- Introduce campaigns and referral rewards after the conditions, funding, fraud controls and payout handling are agreed. Show real progress and terms; avoid invented ratings, scores, offers or promised earnings.
