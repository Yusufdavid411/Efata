import '../models/efata_api_models.dart';

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
