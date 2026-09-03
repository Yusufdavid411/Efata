# Google Maps Integration

This app now uses a minimal Google Maps setup for the current logistics workflow.

## Google APIs Used

- Maps SDK for Android
  - Required to display interactive Google Maps in the Flutter Android app.
- Routes API
  - Used only when both pickup and drop-off coordinates are available and the app needs a delivery route polyline, route distance, and estimated travel duration.

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
- Navigation SDK
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
- `POST_NOTIFICATIONS`
- Google Maps SDK metadata supplied by Gradle manifest placeholder

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
- API restriction: Maps SDK for Android only

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
8. Start transit as a driver and confirm live driver location updates continue to appear.

## Future APIs

Enable these only if a future feature needs them:

- Places API or Places Autocomplete: typed address search and autocomplete.
- Geocoding API: converting map coordinates into human-readable addresses.
- Distance Matrix API: comparing travel distance/time across many drivers or many destinations.
- Navigation SDK: in-app turn-by-turn navigation.
