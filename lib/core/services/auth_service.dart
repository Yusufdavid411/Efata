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

    await _googleSignIn.signOut();
    final googleUser = await _googleSignIn.authenticate();
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

  Future<void> createGoogleProfileIfNeeded({
    required User user,
    required String role,
  }) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    if (!userDoc.exists) {
      await userRef.set({
        'uid': user.uid,
        'name':
            user.displayName ?? user.email?.split('@').first ?? 'EFATA user',
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
          'name': user.displayName ?? user.email?.split('@').first ?? 'Driver',
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
    await _googleSignIn.signOut();
    final googleUser = await _googleSignIn.authenticate();
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
    await _ensureGoogleInitialized();
    await _googleSignIn.signOut();
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
