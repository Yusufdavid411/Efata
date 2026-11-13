import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/efata_backend_config.dart';
import 'efata_api_client.dart';

class EfataSession {
  static const enabled = true;
  static final instance = EfataSession();

  String? _access;
  String? _refresh;
  Future<String?>? _refreshing;
  int _generation = 0;

  bool get signedIn => _access != null;
  String? accountUid;

  Future<void> register(String email, String password, String role) async {
    final response = await http
        .post(
          Uri.parse(EfataBackendConfig.apiOrigin).resolve('/api/auth'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'register',
            'email': email,
            'password': password,
            'role': role,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 202) {
      throw EfataApiException(
        'registration_failed',
        statusCode: response.statusCode,
      );
    }
  }

  Future<void> signIn(String email, String password) async {
    clear();
    final generation = _generation;
    await _exchange('sign_in', {
      'email': email,
      'password': password,
    }, generation);
  }

  void clear() {
    accountUid = null;
    _generation++;
    _access = null;
    _refresh = null;
    _refreshing = null;
  }

  Future<String?> token({required bool refresh}) async {
    final credential = _refresh;
    if (!refresh || credential == null) return _access;
    return _refreshing ??= _renew(credential, _generation);
  }

  Future<String?> _renew(String credential, int generation) async {
    try {
      return await _exchange('refresh', {
        'refreshToken': credential,
      }, generation);
    } finally {
      if (generation == _generation) _refreshing = null;
    }
  }

  Future<String?> _exchange(
    String action,
    Map<String, String> data,
    int generation,
  ) async {
    final response = await http
        .post(
          Uri.parse(EfataBackendConfig.apiOrigin).resolve('/api/auth'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'action': action, ...data}),
        )
        .timeout(const Duration(seconds: 12));
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw EfataApiException(
        'auth_unavailable',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200 ||
        body is! Map ||
        body['accessToken'] is! String ||
        body['refreshToken'] is! String) {
      throw EfataApiException(
        body is Map
            ? body['error']?.toString() ?? 'auth_unavailable'
            : 'auth_unavailable',
        statusCode: response.statusCode,
      );
    }
    if (generation != _generation) return null;
    _access = body['accessToken'] as String;
    _refresh = body['refreshToken'] as String;
    return _access;
  }
}
