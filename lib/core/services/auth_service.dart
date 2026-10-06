import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

const String googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static const MethodChannel _configChannel = MethodChannel(
    'com.efata.app/config',
  );

  bool _googleInitialized = false;
  String? _resolvedGoogleWebClientId;

  Future<String> _googleClientId() async {
    if (googleWebClientId.isNotEmpty) return googleWebClientId;
    if (_resolvedGoogleWebClientId != null) return _resolvedGoogleWebClientId!;

    try {
      final value = await _configChannel.invokeMethod<String>(
        'googleWebClientId',
      );
      _resolvedGoogleWebClientId = value?.trim() ?? '';
    } catch (_) {
      _resolvedGoogleWebClientId = '';
    }

    return _resolvedGoogleWebClientId!;
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    final clientId = await _googleClientId();
    await _googleSignIn.initialize(
      serverClientId: clientId.isEmpty ? null : clientId,
    );
    _googleInitialized = true;
  }

  // Register User
  Future<User?> register({
    required String email,
    required String password,
    required String role,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await _firestore.collection('users').doc(credential.user!.uid).set({
      'email': email,
      'role': role,
      'createdAt': Timestamp.now(),
    });

    return credential.user;
  }

  // Login User
  Future<User?> login({required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    return credential.user;
  }

  Future<UserCredential> signInWithGoogle() async {
    final clientId = await _googleClientId();
    if (clientId.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-google-web-client-id',
        message:
            'Google login needs the Firebase Web client ID before it can work on Android.',
      );
    }

    await _ensureGoogleInitialized();

    if (!_googleSignIn.supportsAuthenticate()) {
      throw FirebaseAuthException(
        code: 'google-sign-in-unavailable',
        message: 'Google sign-in is not available on this device.',
      );
    }

    final googleUser = await _authenticateWithGoogle();
    final googleAuth = googleUser.authentication;

    if (googleAuth.idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-token',
        message: 'Google did not return a valid sign-in token.',
      );
    }

    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    return _auth.signInWithCredential(credential);
  }

  Future<GoogleSignInAccount> _authenticateWithGoogle() async {
    try {
      return await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      throw _googleExceptionToFirebaseAuth(e);
    }
  }

  FirebaseAuthException _googleExceptionToFirebaseAuth(
    GoogleSignInException exception,
  ) {
    final details = exception.details?.toString() ?? '';
    final description = exception.description ?? '';
    final combined = '$description $details'.toLowerCase();

    if (exception.code == GoogleSignInExceptionCode.canceled &&
        combined.contains('account reauth failed')) {
      return FirebaseAuthException(
        code: 'google-account-reauth-failed',
        message:
            'Google could not verify this account on the device. Update Google Play Services or remove and add the Google account again, then retry.',
      );
    }

    return switch (exception.code) {
      GoogleSignInExceptionCode.canceled => FirebaseAuthException(
        code: 'google-sign-in-cancelled',
        message: 'Google sign-in was cancelled.',
      ),
      GoogleSignInExceptionCode.clientConfigurationError => FirebaseAuthException(
        code: 'google-client-configuration-error',
        message:
            'Google login is not fully configured for this app build. Check the Web Client ID, package name, and SHA fingerprint.',
      ),
      GoogleSignInExceptionCode.providerConfigurationError =>
        FirebaseAuthException(
          code: 'google-provider-configuration-error',
          message:
              'Google login is not fully configured on this device or Firebase project.',
        ),
      GoogleSignInExceptionCode.uiUnavailable => FirebaseAuthException(
        code: 'google-ui-unavailable',
        message: 'Google sign-in cannot open on this screen. Please try again.',
      ),
      GoogleSignInExceptionCode.interrupted => FirebaseAuthException(
        code: 'google-sign-in-interrupted',
        message: 'Google sign-in was interrupted. Please try again.',
      ),
      _ => FirebaseAuthException(
        code: 'google-sign-in-failed',
        message: exception.description ?? 'Google sign-in failed.',
      ),
    };
  }

  Future<String?> ensureGoogleProfile({
    required User user,
    String? preferredRole,
  }) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    if (userDoc.exists) {
      final role = userDoc.data()?['role']?.toString();
      await userRef.set({
        'uid': user.uid,
        'email': user.email,
        'photoUrl': user.photoURL,
        'googleLinked': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return role?.isNotEmpty == true ? role : preferredRole;
    }

    final email = user.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      final existing = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        final existingDoc = existing.docs.first;
        final existingData = existingDoc.data();
        final existingRole = existingData['role']?.toString();
        final resolvedRole = existingRole?.isNotEmpty == true
            ? existingRole!
            : preferredRole;

        await userRef.set({
          ...existingData,
          'uid': user.uid,
          'email': email,
          'role': resolvedRole,
          'photoUrl': existingData['photoUrl'] ?? user.photoURL,
          'googleLinked': true,
          'authProvider': existingData['authProvider'] == 'password'
              ? 'email_google'
              : (existingData['authProvider'] ?? 'google'),
          'migratedFromUid': existingDoc.id == user.uid ? null : existingDoc.id,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (resolvedRole == 'driver') {
          await _copyDriverProfileIfNeeded(
            fromUid: existingDoc.id,
            toUid: user.uid,
            user: user,
          );
        }

        return resolvedRole;
      }
    }

    if (preferredRole == null || preferredRole.isEmpty) return null;
    await createGoogleProfileIfNeeded(user: user, role: preferredRole);
    return preferredRole;
  }

  Future<void> _copyDriverProfileIfNeeded({
    required String fromUid,
    required String toUid,
    required User user,
  }) async {
    final driverRef = _firestore.collection('drivers').doc(toUid);
    final driverDoc = await driverRef.get();
    if (driverDoc.exists) return;

    final oldDriverDoc = await _firestore
        .collection('drivers')
        .doc(fromUid)
        .get();
    if (oldDriverDoc.exists) {
      await driverRef.set({
        ...oldDriverDoc.data()!,
        'uid': toUid,
        'driverId': toUid,
        'email': user.email,
        'photoUrl': oldDriverDoc.data()?['photoUrl'] ?? user.photoURL,
        'googleLinked': true,
        'migratedFromUid': fromUid == toUid ? null : fromUid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    await driverRef.set({
      'uid': toUid,
      'driverId': toUid,
      'name': user.displayName ?? '',
      'fullName': user.displayName ?? '',
      'email': user.email,
      'photoUrl': user.photoURL,
      'isAvailable': false,
      'isOnline': false,
      'profileCompleted': false,
      'licenseUploaded': false,
      'verificationStatus': 'incomplete',
      'authProvider': 'google',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createGoogleProfileIfNeeded({
    required User user,
    required String role,
  }) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    if (!userDoc.exists) {
      await userRef.set({
        'uid': user.uid,
        'name': user.displayName ?? '',
        'fullName': user.displayName ?? '',
        'email': user.email,
        'photoUrl': user.photoURL,
        'role': role,
        'authProvider': 'google',
        'profileCompleted': false,
        'onboardingSkipped': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (role == 'driver') {
      final driverRef = _firestore.collection('drivers').doc(user.uid);
      final driverDoc = await driverRef.get();

      if (!driverDoc.exists) {
        await driverRef.set({
          'uid': user.uid,
          'driverId': user.uid,
          'name': user.displayName ?? '',
          'fullName': user.displayName ?? '',
          'email': user.email,
          'photoUrl': user.photoURL,
          'isAvailable': false,
          'isOnline': false,
          'profileCompleted': false,
          'licenseUploaded': false,
          'verificationStatus': 'incomplete',
          'authProvider': 'google',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  Future<void> sendPasswordSetupEmail() async {
    final email = _auth.currentUser?.email;
    if (email == null || email.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'This account does not have an email address.',
      );
    }

    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> linkCurrentUserWithGoogle() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Sign in before connecting Google.',
      );
    }

    final clientId = await _googleClientId();
    if (clientId.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-google-web-client-id',
        message:
            'Google login needs the Firebase Web client ID before it can work on Android.',
      );
    }

    await _ensureGoogleInitialized();
    final googleUser = await _authenticateWithGoogle();
    final googleAuth = googleUser.authentication;

    if (googleAuth.idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-token',
        message: 'Google did not return a valid sign-in token.',
      );
    }

    if (currentUser.email != null &&
        googleUser.email.toLowerCase() != currentUser.email!.toLowerCase()) {
      throw FirebaseAuthException(
        code: 'google-email-mismatch',
        message:
            'Choose the same Google email as this EFATA account to link them.',
      );
    }

    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    await currentUser.linkWithCredential(credential);
    await currentUser.reload();

    await _firestore.collection('users').doc(currentUser.uid).set({
      'googleLinked': true,
      'authProvider': 'email_google',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  bool currentUserHasPasswordProvider() {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.providerData.any(
      (provider) => provider.providerId == 'password',
    );
  }

  // Logout
  Future<void> logout() async {
    try {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();
    } catch (_) {
      // Firebase sign-out must still happen even if Google Play Services
      // or Google Sign-In configuration is temporarily unavailable.
    }
    await _auth.signOut();
  }

  // Get Current User
  User? get currentUser => _auth.currentUser;

  // Get User Role
  Future<String> getUserRole(String uid) async {
    final data = await getUserData(uid);
    return data?['role']?.toString() ?? '';
  }

  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<Map<String, dynamic>?> getDriverData(String uid) async {
    final doc = await _firestore.collection('drivers').doc(uid).get();
    return doc.data();
  }
}
