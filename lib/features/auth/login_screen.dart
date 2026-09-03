import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:logistics_app/core/services/auth_service.dart';
import 'package:logistics_app/core/services/app_notification_banner_service.dart';

import 'role_selection_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  bool isGoogleLoading = false;
  bool obscurePassword = true;

  final AuthService authService = AuthService();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> loginUser() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      AppNotificationBannerService.error(
        'Please enter email and password.',
        title: 'Missing login details',
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseAuth.instance.signOut();

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw Exception('Login failed. Please try again.');
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      if (!userDoc.exists) {
        AppNotificationBannerService.error(
          'User role not found. Please register again.',
          title: 'Account setup issue',
        );
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final role = userData['role']?.toString();

      if (userData['isSuspended'] == true) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        AppNotificationBannerService.error(
          'This account is suspended. Contact support.',
          title: 'Account suspended',
        );
        return;
      }

      if (role == 'driver') {
        final driverDoc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .get();
        final driverStatus = driverDoc
            .data()?['verificationStatus']
            ?.toString()
            .toLowerCase();

        if (driverStatus == 'suspended' || driverStatus == 'rejected') {
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          AppNotificationBannerService.error(
            driverStatus == 'rejected'
                ? 'This driver account was rejected. Contact support.'
                : 'This driver account is suspended. Contact support.',
            title: 'Driver account blocked',
          );
          return;
        }
      }

      if (!mounted) return;

      if (role == 'customer') {
        Navigator.pushReplacementNamed(context, '/customerHome');
      } else if (role == 'driver') {
        Navigator.pushReplacementNamed(context, '/driverHome');
      } else {
        AppNotificationBannerService.error(
          'Invalid user role.',
          title: 'Account setup issue',
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message = 'Login failed. Please try again.';

      if (e.code == 'invalid-credential') {
        message = 'Incorrect email or password.';
      } else if (e.code == 'user-not-found') {
        message = 'No account found with this email.';
      } else if (e.code == 'wrong-password') {
        message = 'Incorrect password.';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address.';
      } else if (e.code == 'user-disabled') {
        message = 'This account has been disabled.';
      }

      AppNotificationBannerService.error(message, title: 'Login failed');
    } catch (e) {
      if (!mounted) return;

      AppNotificationBannerService.error(e.toString(), title: 'Login failed');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> loginWithGoogle() async {
    setState(() {
      isGoogleLoading = true;
    });

    try {
      await FirebaseAuth.instance.signOut();
      final credential = await authService.signInWithGoogle();
      final user = credential.user;

      if (user == null) {
        throw Exception('Google sign-in failed. Please try again.');
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      String? role = userDoc.data()?['role']?.toString();

      if (userDoc.exists && userDoc.data()?['isSuspended'] == true) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        AppNotificationBannerService.error(
          'This account is suspended. Contact support.',
          title: 'Account suspended',
        );
        return;
      }

      if (role == null || role.isEmpty) {
        if (!mounted) return;
        role = await _chooseGoogleRole();
        if (role == null) {
          await FirebaseAuth.instance.signOut();
          return;
        }

        await authService.createGoogleProfileIfNeeded(user: user, role: role);
      }

      if (role == 'driver') {
        final driverDoc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .get();
        final driverStatus = driverDoc
            .data()?['verificationStatus']
            ?.toString()
            .toLowerCase();

        if (driverStatus == 'suspended' || driverStatus == 'rejected') {
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          AppNotificationBannerService.error(
            driverStatus == 'rejected'
                ? 'This driver account was rejected. Contact support.'
                : 'This driver account is suspended. Contact support.',
            title: 'Driver account blocked',
          );
          return;
        }
      }

      if (!mounted) return;

      if (role == 'customer') {
        Navigator.pushReplacementNamed(context, '/customerHome');
      } else if (role == 'driver') {
        final driverDoc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .get();
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          driverDoc.exists ? '/driverHome' : '/driverOnboarding',
        );
      } else {
        AppNotificationBannerService.error(
          'Invalid user role.',
          title: 'Account setup issue',
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      final message = switch (e.code) {
        'account-exists-with-different-credential' =>
          'This email already uses another login method.',
        'google-sign-in-unavailable' => 'Google sign-in is unavailable here.',
        'missing-google-token' => 'Google sign-in could not be verified.',
        'missing-google-web-client-id' =>
          'Google login needs the Web client ID to be added to this build.',
        _ => e.message ?? 'Google sign-in failed. Please try again.',
      };

      AppNotificationBannerService.error(message, title: 'Google login failed');
    } catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        e.toString(),
        title: 'Google login failed',
      );
    } finally {
      if (mounted) {
        setState(() {
          isGoogleLoading = false;
        });
      }
    }
  }

  Future<String?> _chooseGoogleRole() {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Continue as',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose how you want to use EFATA with this Google account.',
                  style: TextStyle(color: Color(0xFF64748B), height: 1.35),
                ),
                const SizedBox(height: 18),
                _RoleChoiceTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Customer',
                  subtitle: 'Book and track deliveries.',
                  onTap: () => Navigator.pop(context, 'customer'),
                ),
                const SizedBox(height: 10),
                _RoleChoiceTile(
                  icon: Icons.local_shipping_outlined,
                  title: 'Driver',
                  subtitle: 'Accept delivery jobs after verification.',
                  onTap: () => Navigator.pop(context, 'driver'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Welcome back',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 32,
                  height: 1.06,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to book deliveries, track trips, and manage your EFATA account.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 30),
              _GoogleSignInButton(
                isLoading: isGoogleLoading,
                onPressed: isLoading || isGoogleLoading
                    ? null
                    : loginWithGoogle,
              ),
              const SizedBox(height: 18),
              const _DividerLabel(label: 'or continue with email'),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isLoading || isGoogleLoading
                              ? null
                              : loginUser,
                          child: Text(isLoading ? 'Signing in...' : 'Sign In'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RoleSelectionScreen(),
                            ),
                          );
                        },
                  child: const Text('Create a new EFATA account'),
                ),
              ),
              const SizedBox(height: 18),
              const _TrustStrip(),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleMark(),
                  SizedBox(width: 12),
                  Text(
                    'Continue with Google',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'G',
      style: TextStyle(
        color: Color(0xFF4285F4),
        fontSize: 24,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFCBD5E1))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFCBD5E1))),
      ],
    );
  }
}

class _RoleChoiceTile extends StatelessWidget {
  const _RoleChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _TrustItem(icon: Icons.route_rounded, label: 'Live tracking'),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _TrustItem(
            icon: Icons.verified_user_outlined,
            label: 'Verified drivers',
          ),
        ),
      ],
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
