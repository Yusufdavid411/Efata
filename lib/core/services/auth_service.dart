import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _googleInitialized = false;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await _googleSignIn.initialize();
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
        'name': user.displayName ?? user.email?.split('@').first ?? 'EFATA user',
        'email': user.email,
        'photoUrl': user.photoURL,
        'role': role,
        'authProvider': 'google',
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
