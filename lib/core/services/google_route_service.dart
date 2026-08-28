import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

const String googleRoutesApiKey = String.fromEnvironment(
  'GOOGLE_ROUTES_API_KEY',
);

class GoogleRouteResult {
  const GoogleRouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final int distanceMeters;
  final int durationSeconds;

  double get distanceKm => distanceMeters / 1000;
  int get durationMinutes => (durationSeconds / 60).round();
}

class GoogleRouteService {
  GoogleRouteService._();

  static final Map<String, Future<GoogleRouteResult?>> _requestCache = {};

  static Future<GoogleRouteResult?> routeBetween({
    required LatLng pickup,
    required LatLng dropoff,
  }) {
    if (googleRoutesApiKey.isEmpty) return Future.value(null);

    final key = _routeKey(pickup, dropoff);

    return _requestCache.putIfAbsent(
      key,
      () => _fetchRoute(pickup: pickup, dropoff: dropoff),
    );
  }

  static String _routeKey(LatLng pickup, LatLng dropoff) {
    return [
      pickup.latitude.toStringAsFixed(6),
      pickup.longitude.toStringAsFixed(6),
      dropoff.latitude.toStringAsFixed(6),
      dropoff.longitude.toStringAsFixed(6),
    ].join(',');
  }

  static Future<GoogleRouteResult?> _fetchRoute({
    required LatLng pickup,
    required LatLng dropoff,
  }) async {
    final response = await http
        .post(
          Uri.https('routes.googleapis.com', '/directions/v2:computeRoutes'),
          headers: const {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': googleRoutesApiKey,
            'X-Goog-FieldMask':
                'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
          },
          body: jsonEncode({
            'origin': {
              'location': {
                'latLng': {
                  'latitude': pickup.latitude,
                  'longitude': pickup.longitude,
                },
              },
            },
            'destination': {
              'location': {
                'latLng': {
                  'latitude': dropoff.latitude,
                  'longitude': dropoff.longitude,
                },
              },
            },
            'travelMode': 'DRIVE',
            'routingPreference': 'TRAFFIC_UNAWARE',
            'polylineQuality': 'OVERVIEW',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = body['routes'] as List<dynamic>? ?? [];
    if (routes.isEmpty) return null;

    final route = routes.first as Map<String, dynamic>;
    final encodedPolyline =
        (route['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
            ?.toString();

    if (encodedPolyline == null || encodedPolyline.isEmpty) return null;

    return GoogleRouteResult(
      points: _decodePolyline(encodedPolyline),
      distanceMeters: (route['distanceMeters'] as num?)?.toInt() ?? 0,
      durationSeconds: _parseDuration(route['duration']),
    );
  }

  static int _parseDuration(dynamic value) {
    final text = value?.toString() ?? '';
    if (!text.endsWith('s')) return 0;
    return double.tryParse(text.substring(0, text.length - 1))?.round() ?? 0;
  }

  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);

      lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      shift = 0;
      result = 0;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);

      lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }
}
