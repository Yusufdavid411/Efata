import 'package:cloud_functions/cloud_functions.dart';

class EmailRegistrationService {
  EmailRegistrationService._();

  static final instance = EmailRegistrationService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  Future<void> sendRegistrationCode({
    required String email,
    required String role,
  }) async {
    await _call('sendRegistrationCode', {'email': email, 'role': role});
  }

  Future<void> verifyRegistrationCode({
    required String email,
    required String role,
    required String code,
  }) async {
    await _call('verifyRegistrationCode', {
      'email': email,
      'role': role,
      'code': code,
    });
  }

  Future<void> completeRegistration({
    required String email,
    required String role,
    required String code,
    required String password,
  }) async {
    await _call('completeRegistration', {
      'email': email,
      'role': role,
      'code': code,
      'password': password,
    });
  }

  Future<dynamic> _call(String name, Map<String, dynamic> data) async {
    try {
      final callable = _functions.httpsCallable(name);
      final response = await callable.call<dynamic>(data);
      return response.data;
    } on FirebaseFunctionsException catch (e) {
      throw EmailRegistrationException(_friendlyMessage(e), code: e.code);
    } catch (_) {
      throw const EmailRegistrationException(
        'Network issue. Please check your connection and try again.',
      );
    }
  }

  String _friendlyMessage(FirebaseFunctionsException e) {
    final message = e.message?.trim();
    if (message != null && message.isNotEmpty) return message;

    return switch (e.code) {
      'already-exists' => 'This email already has an EFATA account.',
      'invalid-argument' => 'Check the details and try again.',
      'deadline-exceeded' => 'Your code has expired. Request a new one.',
      'permission-denied' => 'The EFATA code is not correct.',
      'resource-exhausted' => 'Too many attempts. Please try again later.',
      'failed-precondition' => 'EFATA email sender is not configured yet.',
      'unavailable' => 'EFATA could not send the code email. Try again.',
      _ => 'Registration service is unavailable. Please try again.',
    };
  }
}

class EmailRegistrationException implements Exception {
  const EmailRegistrationException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
