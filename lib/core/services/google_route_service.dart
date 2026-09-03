import 'dart:convert';

import 'package:flutter/services.dart';
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

  static const MethodChannel _configChannel = MethodChannel(
    'com.efata.app/config',
  );
  static const int _maxCachedRoutes = 80;

  static final Map<String, Future<GoogleRouteResult?>> _requestCache = {};
  static String? _runtimeApiKey;

  static Future<GoogleRouteResult?> routeBetween({
    required LatLng pickup,
    required LatLng dropoff,
    int cachePrecision = 6,
  }) async {
    final apiKey = await _apiKey();
    if (apiKey.isEmpty) return null;

    final key = _routeKey(pickup, dropoff, precision: cachePrecision);
    if (_requestCache.length > _maxCachedRoutes &&
        !_requestCache.containsKey(key)) {
      _requestCache.remove(_requestCache.keys.first);
    }

    return _requestCache.putIfAbsent(
      key,
      () => _fetchRoute(apiKey: apiKey, pickup: pickup, dropoff: dropoff),
    );
  }

  static Future<String> _apiKey() async {
    if (googleRoutesApiKey.isNotEmpty) return googleRoutesApiKey;
    if (_runtimeApiKey != null) return _runtimeApiKey!;

    try {
      _runtimeApiKey =
          await _configChannel.invokeMethod<String>('googleRoutesApiKey') ?? '';
    } catch (_) {
      _runtimeApiKey = '';
    }

    return _runtimeApiKey!;
  }

  static String _routeKey(
    LatLng pickup,
    LatLng dropoff, {
    required int precision,
  }) {
    return [
      pickup.latitude.toStringAsFixed(precision),
      pickup.longitude.toStringAsFixed(precision),
      dropoff.latitude.toStringAsFixed(precision),
      dropoff.longitude.toStringAsFixed(precision),
    ].join(',');
  }

  static Future<GoogleRouteResult?> _fetchRoute({
    required String apiKey,
    required LatLng pickup,
    required LatLng dropoff,
  }) async {
    final response = await http
        .post(
          Uri.https('routes.googleapis.com', '/directions/v2:computeRoutes'),
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': apiKey,
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
