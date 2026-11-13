import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/efata_backend_config.dart';
import '../models/efata_api_models.dart';
import 'efata_api_client.dart';

class AccountAccess {
  const AccountAccess({
    required this.role,
    required this.accountStatus,
    required this.profileCompleted,
    this.driverVerificationStatus,
  });

  final String role;
  final String accountStatus;
  final bool profileCompleted;
  final String? driverVerificationStatus;

  bool get isBlocked =>
      accountStatus != 'active' ||
      driverVerificationStatus == 'suspended' ||
      driverVerificationStatus == 'rejected';

  String get homeRoute => role == 'driver' ? '/driverHome' : '/customerHome';

  String get onboardingRoute =>
      role == 'driver' ? '/driverOnboarding' : '/customerOnboarding';

  String get landingRoute => profileCompleted ? homeRoute : onboardingRoute;

  factory AccountAccess.fromApi(EfataAccount account) => AccountAccess(
    role: account.role,
    accountStatus: account.accountStatus,
    profileCompleted: account.profileCompleted,
    driverVerificationStatus: account.driverProfile?['verificationStatus']
        ?.toString()
        .toLowerCase(),
  );
}

class AccountAccessService {
  AccountAccessService({
    EfataApiClient? apiClient,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _apiClient = apiClient ?? EfataApiClient.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final EfataApiClient _apiClient;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<AccountAccess?> loadCurrent() async {
    if (EfataBackendConfig.useNewBackend) {
      try {
        return AccountAccess.fromApi(await _apiClient.getMe());
      } on EfataApiException catch (error) {
        if (error.statusCode == 404 && error.code == 'account_not_found') {
          final legacy = await _loadFromFirestore();
          if (legacy == null || !['customer', 'driver'].contains(legacy.role)) {
            return null;
          }
          return AccountAccess.fromApi(
            await _apiClient.bootstrapAccount(role: legacy.role),
          );
        }
        rethrow;
      }
    }
    return _loadFromFirestore();
  }

  Future<AccountAccess> bootstrap({required String role}) async {
    if (EfataBackendConfig.useNewBackend) {
      return AccountAccess.fromApi(
        await _apiClient.bootstrapAccount(role: role),
      );
    }
    final account = await _loadFromFirestore();
    if (account == null) {
      throw const EfataApiException('account_not_found', statusCode: 404);
    }
    return account;
  }

  Future<AccountAccess?> _loadFromFirestore() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (!userDoc.exists) return null;
    final data = userDoc.data() ?? const <String, dynamic>{};
    final role = data['role']?.toString() ?? '';
    String? driverStatus;
    var profileCompleted = data['profileCompleted'] == true;
    if (role == 'driver') {
      final driverDoc = await _firestore
          .collection('drivers')
          .doc(user.uid)
          .get();
      final driver = driverDoc.data() ?? const <String, dynamic>{};
      driverStatus = driver['verificationStatus']?.toString().toLowerCase();
      profileCompleted = driver['profileCompleted'] == true;
    }
    return AccountAccess(
      role: role,
      accountStatus: data['isSuspended'] == true ? 'disabled' : 'active',
      profileCompleted: profileCompleted,
      driverVerificationStatus: driverStatus,
    );
  }
}
