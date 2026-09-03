# Google Maps Integration

This app now uses a minimal Google Maps setup for the current logistics workflow.

## Google APIs Used

- Maps SDK for Android
  - Required to display interactive Google Maps in the Flutter Android app.
- Routes API
  - Used only when both pickup and drop-off coordinates are available and the app needs a delivery route polyline, route distance, and estimated travel duration.
- Navigation SDK
  - Used on the driver current-job flow for in-app voice turn-by-turn guidance after the driver starts navigation.
  - The SDK handles road routing, rerouting, voice prompts, and navigation UI inside EFATA.

## Google APIs Deliberately Avoided

The app does not use these APIs at this stage:

- Places API
- Places Autocomplete
- Distance Matrix API
- Roads API
- Street View
- Elevation API
- Maps Static API
- Maps Embed API
- Geolocation API
- Address Validation API
- Geocoding API

Address search was removed to avoid Places/Autocomplete billing. Customers can pick a point on the map, use device GPS, or reuse pickup/drop-off locations from previous orders.

## Key Configuration

Do not hardcode keys in Dart or Android source files.

For local Android builds, add this to `android/local.properties`:

```properties
GOOGLE_MAPS_ANDROID_API_KEY=your_android_maps_sdk_key
GOOGLE_ROUTES_API_KEY=your_routes_api_key
```

For route drawing, either use `GOOGLE_ROUTES_API_KEY` in `android/local.properties` or pass it at build/run time:

```powershell
C:\src\flutter\bin\flutter.bat run --dart-define=GOOGLE_ROUTES_API_KEY=your_routes_api_key
```

or:

```powershell
C:\src\flutter\bin\flutter.bat build apk --debug --dart-define=GOOGLE_ROUTES_API_KEY=your_routes_api_key
```

If `GOOGLE_ROUTES_API_KEY` is not provided, the map still loads and shows pickup/drop-off markers with a direct fallback line instead of a billed route.

## Android Configuration

The Android manifest includes:

- `INTERNET`
- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION`
- `POST_NOTIFICATIONS`
- Google Maps SDK metadata supplied by Gradle manifest placeholder

The Android app now uses `minSdk = 24` because the Google Navigation Flutter SDK requires Android API level 24 or newer.

The current Android package/application ID is:

```text
com.example.logistics_app
```

Before production, change this package ID to the final EFATA package name and update Google Cloud key restrictions accordingly.

## Google Cloud Console Restrictions

Create separate keys where possible.

Android Maps SDK key:

- Application restriction: Android apps
- Package name: `com.example.logistics_app`
- SHA-1 certificate fingerprint: use the debug SHA-1 for testing and release SHA-1 for production
- API restriction: Maps SDK for Android and Navigation SDK

Routes API key:

- API restriction: Routes API only
- For production, prefer moving Routes API calls behind a backend function and restrict this key by server/IP.
- For short-term app testing without a backend proxy, keep this as a separate Routes-only key and rotate it before launch.

Do not enable other Maps Platform APIs unless a future feature genuinely requires them.

## Billing Controls

- The map display uses Maps SDK only.
- The app does not call Places or Geocoding while typing.
- Saved pickup/drop-off suggestions come from existing Firestore orders.
- Routes API calls are cached by pickup/drop-off coordinate pair.
- Driver rerouting calls are cached by rounded driver/target coordinate pair.
- Driver rerouting is debounced and only recalculates after the target changes, or after the driver moves about 90 meters and at least 25 seconds have passed.
- Route requests are not triggered by map camera movement.
- Route requests are not triggered on every widget rebuild.
- If the pickup/drop-off coordinates do not change, no new route request is made.
- If Routes API fails or the key is missing, the app falls back to a direct line.
- Voice navigation only starts when the driver taps Start Voice Navigation or Voice Navigation on the current-job screen.
- Navigation SDK location writes back to Firestore are throttled to about once every 5 seconds so the customer map can update without excessive writes.

## Testing

1. Add `GOOGLE_MAPS_ANDROID_API_KEY` and `GOOGLE_ROUTES_API_KEY` to `android/local.properties`.
2. Confirm the Routes key is restricted to Routes API only.
3. Open customer booking.
4. Tap the map icon for pickup and drop-off.
5. Allow location permission and test the current-location button.
6. Create an order.
7. Open tracking and confirm:
   - Google Map loads.
   - Pickup marker appears.
   - Drop-off marker appears.
   - Driver/current location appears when available.
   - Route line appears when Routes API key is provided.
   - Direct fallback line appears if Routes API is not configured.
8. Accept a job as a driver and confirm the current job opens with the large live map.
9. Tap Start Voice Navigation.
10. Accept the Google navigation terms on the first run.
11. Confirm:
   - Google turn-by-turn navigation opens inside EFATA.
   - Spoken guidance is enabled.
   - The map follows the driver location.
   - The route reroutes if the driver leaves the original road path.
   - Customer tracking continues to receive driver location updates.

## Future APIs

Enable these only if a future feature needs them:

- Places API or Places Autocomplete: typed address search and autocomplete.
- Geocoding API: converting map coordinates into human-readable addresses.
- Distance Matrix API: comparing travel distance/time across many drivers or many destinations.
- Places API or Places Autocomplete should be considered later if the app needs Google-powered typed address suggestions instead of the current Firestore history and map-pick flow.
