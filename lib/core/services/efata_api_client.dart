import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/efata_backend_config.dart';
import '../models/efata_api_models.dart';

typedef EfataTokenProvider = Future<String?> Function({required bool refresh});

class EfataApiException implements Exception {
  const EfataApiException(this.code, {required this.statusCode});

  final String code;
  final int statusCode;

  @override
  String toString() => 'EfataApiException($statusCode, $code)';
}

class EfataApiClient {
  EfataApiClient({
    http.Client? httpClient,
    EfataTokenProvider? tokenProvider,
    String apiOrigin = EfataBackendConfig.apiOrigin,
  }) : _httpClient = httpClient ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseToken,
       _apiOrigin = Uri.parse(apiOrigin);

  static final instance = EfataApiClient();

  final http.Client _httpClient;
  final EfataTokenProvider _tokenProvider;
  final Uri _apiOrigin;

  static Future<String?> _firebaseToken({required bool refresh}) async {
    return await FirebaseAuth.instance.currentUser?.getIdToken(refresh);
  }

  Future<EfataAccount> getMe() async {
    final json = await _request('GET', '/api/me');
    return EfataAccount.fromJson(_map(json['account']));
  }

  Future<EfataAccount> bootstrapAccount({String? role}) async {
    final json = await _request(
      'POST',
      '/api/account-bootstrap',
      body: {if (role != null) 'role': role},
    );
    return EfataAccount.fromJson(_map(json['account']));
  }

  Future<EfataOrderPage> listOrders({
    String scope = 'mine',
    String? status,
    int page = 1,
  }) async {
    final json = await _request(
      'GET',
      '/api/orders',
      query: {
        'scope': scope,
        'page': '$page',
        if (status != null) 'status': status,
      },
    );
    return EfataOrderPage.fromJson(json);
  }

  Future<EfataOrder> getOrder(String orderId) async {
    final json = await _request('GET', '/api/orders', query: {'id': orderId});
    return EfataOrder.fromJson(_map(json['order']));
  }

  Future<EfataOrder> createOrder({
    required String pickup,
    required double pickupLat,
    required double pickupLng,
    required String dropoff,
    required double dropoffLat,
    required double dropoffLng,
    required String item,
    required String vehicleType,
    required String paymentMethod,
    required double amount,
    DateTime? scheduledFor,
  }) async {
    final json = await _request(
      'POST',
      '/api/orders',
      body: {
        'pickup': {'label': pickup, 'lat': pickupLat, 'lng': pickupLng},
        'dropoff': {'label': dropoff, 'lat': dropoffLat, 'lng': dropoffLng},
        'item': item,
        'vehicleType': vehicleType,
        'paymentMethod': paymentMethod,
        'amount': amount,
        if (scheduledFor != null)
          'scheduledFor': scheduledFor.toUtc().toIso8601String(),
      },
    );
    return EfataOrder.fromJson(_map(json['order']));
  }

  Future<EfataOrder> transitionOrder(String orderId, String action) async {
    final json = await _request(
      'POST',
      '/api/order-action',
      body: {'orderId': orderId, 'action': action},
    );
    return EfataOrder.fromJson(_map(json['order']));
  }

  Future<EfataMessagePage> listMessages(String orderId, {int page = 1}) async {
    final json = await _request(
      'GET',
      '/api/messages',
      query: {'orderId': orderId, 'page': '$page'},
    );
    return EfataMessagePage.fromJson(json);
  }

  Future<EfataMessage> sendMessage(String orderId, String text) async {
    final json = await _request(
      'POST',
      '/api/messages',
      body: {'orderId': orderId, 'text': text},
    );
    return EfataMessage.fromJson(_map(json['message']));
  }

  Future<void> markMessagesRead(String orderId) async {
    await _request('PATCH', '/api/messages', body: {'orderId': orderId});
  }

  Future<EfataDriverTracking> setDriverAvailability({
    required bool online,
    double? lat,
    double? lng,
    double? heading,
  }) async {
    final json = await _request(
      'POST',
      '/api/driver-availability',
      body: {
        'online': online,
        if (lat != null && lng != null)
          'location': {
            'lat': lat,
            'lng': lng,
            if (heading != null) 'heading': heading,
          },
      },
    );
    return EfataDriverTracking.fromJson(_map(json['availability']));
  }

  Future<EfataDriverTracking> updateDriverLocation({
    required double lat,
    required double lng,
    double? heading,
  }) async {
    final json = await _request(
      'POST',
      '/api/driver-location',
      body: {'lat': lat, 'lng': lng, if (heading != null) 'heading': heading},
    );
    return EfataDriverTracking.fromJson(_map(json['tracking']));
  }

  Future<EfataDriverTracking?> getDriverLocation(String orderId) async {
    final json = await _request(
      'GET',
      '/api/driver-location',
      query: {'orderId': orderId},
    );
    final tracking = json['tracking'];
    return tracking is Map
        ? EfataDriverTracking.fromJson(tracking.cast<String, dynamic>())
        : null;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    var response = await _send(
      method,
      path,
      query: query,
      body: body,
      refreshToken: false,
    );
    if (response.statusCode == 401) {
      response = await _send(
        method,
        path,
        query: query,
        body: body,
        refreshToken: true,
      );
    }
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EfataApiException(
        decoded['error']?.toString() ?? 'request_failed',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    required bool refreshToken,
  }) async {
    final token = await _tokenProvider(refresh: refreshToken);
    if (token == null || token.isEmpty) {
      throw const EfataApiException('session_required', statusCode: 401);
    }
    final uri = _apiOrigin.replace(
      path: path,
      queryParameters: query?.isEmpty == false ? query : null,
    );
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final encodedBody = body == null ? null : jsonEncode(body);
    return switch (method) {
      'GET' => _httpClient.get(uri, headers: headers),
      'POST' => _httpClient.post(uri, headers: headers, body: encodedBody),
      'PATCH' => _httpClient.patch(uri, headers: headers, body: encodedBody),
      _ => throw ArgumentError.value(method, 'method'),
    };
  }

  static Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{};
    } on FormatException {
      throw const EfataApiException('invalid_server_response', statusCode: 502);
    }
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

  void close() => _httpClient.close();
}
