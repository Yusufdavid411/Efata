import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/app_notification_banner_service.dart';

class RegistrationFlowScreen extends StatefulWidget {
  const RegistrationFlowScreen({
    super.key,
    required this.role,
    required this.title,
    required this.subtitle,
    required this.onboardingRoute,
  });

  final String role;
  final String title;
  final String subtitle;
  final String onboardingRoute;

  @override
  State<RegistrationFlowScreen> createState() => _RegistrationFlowScreenState();
}

class _RegistrationFlowScreenState extends State<RegistrationFlowScreen> {
  final emailController = TextEditingController();
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  int step = 0;
  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  String? issuedCode;
  DateTime? codeExpiresAt;
  String? pendingUserId;
  String? reservedEmail;

  @override
  void dispose() {
    emailController.dispose();
    codeController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  bool get isDriver => widget.role == 'driver';

  String get email => emailController.text.trim().toLowerCase();

  bool get codeStillValid {
    final expiresAt = codeExpiresAt;
    return issuedCode != null &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt);
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  String _generateCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  String _generateTemporaryPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%';
    final random = Random.secure();
    return List.generate(28, (_) => chars[random.nextInt(chars.length)]).join();
  }

  String _nameFromEmail(String value) {
    final rawName = value.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ');
    return rawName
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  Future<void> sendCode() async {
    if (!_isValidEmail(email)) {
      AppNotificationBannerService.error(
        'Enter a valid email address to receive your EFATA code.',
        title: 'Check email',
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      if (pendingUserId == null || reservedEmail != email) {
        await _discardPendingRegistration();
        await FirebaseAuth.instance.signOut();

        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: email,
              password: _generateTemporaryPassword(),
            );

        pendingUserId = credential.user?.uid;
        reservedEmail = email;

        if (pendingUserId == null) {
          throw Exception('Email could not be reserved. Please try again.');
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      final message = switch (e.code) {
        'email-already-in-use' => 'This email already has an EFATA account.',
        'invalid-email' => 'Enter a valid email address.',
        'operation-not-allowed' =>
          'Email registration is not enabled yet. Please contact support.',
        'too-many-requests' =>
          'Too many attempts. Please wait a moment and try again.',
        'network-request-failed' =>
          'Network issue. Please check your connection and try again.',
        _ => e.message ?? 'Email check failed. Please try again.',
      };

      AppNotificationBannerService.error(message, title: 'Check email');
      setState(() => isLoading = false);
      return;
    } catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(e.toString(), title: 'Check email');
      setState(() => isLoading = false);
      return;
    }

    if (!mounted) return;

    setState(() {
      issuedCode = _generateCode();
      codeExpiresAt = DateTime.now().add(const Duration(minutes: 10));
      codeController.clear();
      step = 1;
      isLoading = false;
    });

    AppNotificationBannerService.success(
      'Use code $issuedCode to continue testing this flow.',
      title: 'EFATA code ready',
    );
  }

  void verifyCode() {
    if (!codeStillValid) {
      AppNotificationBannerService.error(
        'Your code has expired. Request a new EFATA code.',
        title: 'Code expired',
      );
      return;
    }

    if (codeController.text.trim() != issuedCode) {
      AppNotificationBannerService.error(
        'The code you entered does not match the EFATA code.',
        title: 'Wrong code',
      );
      return;
    }

    setState(() => step = 2);
    AppNotificationBannerService.success(
      'Email confirmed. Create a secure password.',
      title: 'Email verified',
    );
  }

  Future<void> createAccount() async {
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (password.length < 6) {
      AppNotificationBannerService.error(
        'Password must be at least 6 characters.',
        title: 'Password too short',
      );
      return;
    }

    if (password != confirmPassword) {
      AppNotificationBannerService.error(
        'Both passwords must be exactly the same.',
        title: 'Passwords do not match',
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null || user.uid != pendingUserId) {
        throw Exception(
          'Registration session expired. Please request a new EFATA code.',
        );
      }

      final displayName = _nameFromEmail(email);
      await user.updatePassword(password);
      await user.updateDisplayName(displayName);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': displayName,
        'fullName': displayName,
        'email': email,
        'role': widget.role,
        'authProvider': 'email',
        'emailVerifiedByCode': true,
        'profileCompleted': false,
        'onboardingSkipped': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (isDriver) {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .set({
              'uid': user.uid,
              'driverId': user.uid,
              'name': displayName,
              'fullName': displayName,
              'email': email,
              'isAvailable': false,
              'isOnline': false,
              'profileCompleted': false,
              'onboardingSkipped': false,
              'licenseUploaded': false,
              'verificationStatus': 'incomplete',
              'authProvider': 'email',
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }

      if (!mounted) return;

      AppNotificationBannerService.success(
        'Your account is ready. Complete your profile next.',
        title: 'Welcome to EFATA',
      );

      Navigator.pushNamedAndRemoveUntil(
        context,
        widget.onboardingRoute,
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'invalid-email' => 'Enter a valid email address.',
        'weak-password' => 'Use a stronger password for this account.',
        'requires-recent-login' =>
          'Registration session expired. Please request a new EFATA code.',
        _ => e.message ?? 'Account creation failed. Please try again.',
      };
      AppNotificationBannerService.error(message, title: 'Registration failed');
    } catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        e.toString(),
        title: 'Registration failed',
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _discardPendingRegistration() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && pendingUserId != null && user.uid == pendingUserId) {
      await user.delete();
      await FirebaseAuth.instance.signOut();
    }
    pendingUserId = null;
    reservedEmail = null;
    issuedCode = null;
    codeExpiresAt = null;
  }

  Future<void> goBackOneStep() async {
    if (step == 0) {
      Navigator.pop(context);
      return;
    }
    if (step == 1) {
      setState(() => isLoading = true);
      await _discardPendingRegistration();
      if (!mounted) return;
      setState(() {
        isLoading = false;
        step = 0;
      });
      return;
    }
    setState(() => step -= 1);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: isLoading ? null : goBackOneStep,
        ),
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
          children: [
            Row(
              children: List.generate(3, (index) {
                final active = index <= step;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 5,
                    margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
                    decoration: BoxDecoration(
                      color: active ? color : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, animation) {
                final offset = Tween<Offset>(
                  begin: const Offset(0.05, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: switch (step) {
                0 => _EmailStep(
                  key: const ValueKey('email'),
                  subtitle: widget.subtitle,
                  controller: emailController,
                  isLoading: isLoading,
                  onContinue: sendCode,
                ),
                1 => _CodeStep(
                  key: const ValueKey('code'),
                  email: email,
                  code: issuedCode,
                  controller: codeController,
                  isLoading: isLoading,
                  onVerify: verifyCode,
                  onResend: sendCode,
                ),
                _ => _PasswordStep(
                  key: const ValueKey('password'),
                  passwordController: passwordController,
                  confirmPasswordController: confirmPasswordController,
                  obscurePassword: obscurePassword,
                  obscureConfirmPassword: obscureConfirmPassword,
                  isLoading: isLoading,
                  onTogglePassword: () {
                    setState(() => obscurePassword = !obscurePassword);
                  },
                  onToggleConfirmPassword: () {
                    setState(
                      () => obscureConfirmPassword = !obscureConfirmPassword,
                    );
                  },
                  onCreateAccount: createAccount,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailStep extends StatelessWidget {
  const _EmailStep({
    super.key,
    required this.subtitle,
    required this.controller,
    required this.isLoading,
    required this.onContinue,
  });

  final String subtitle;
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepIcon(icon: Icons.mark_email_read_outlined),
        const SizedBox(height: 22),
        const Text(
          'Start with your email',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          onSubmitted: (_) => isLoading ? null : onContinue(),
        ),
        const SizedBox(height: 18),
        _InfoPanel(
          icon: Icons.verified_user_outlined,
          title: 'Email verification',
          body:
              'EFATA checks your email first, then you create your password and complete your profile.',
        ),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: isLoading ? null : onContinue,
          child: Text(isLoading ? 'Sending code...' : 'Send EFATA Code'),
        ),
      ],
    );
  }
}

class _CodeStep extends StatelessWidget {
  const _CodeStep({
    super.key,
    required this.email,
    required this.code,
    required this.controller,
    required this.isLoading,
    required this.onVerify,
    required this.onResend,
  });

  final String email;
  final String? code;
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onVerify;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepIcon(icon: Icons.password_outlined),
        const SizedBox(height: 22),
        const Text(
          'Enter your code',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'We prepared an EFATA verification code for $email.',
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDFA),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF99F6E4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EFATA verification code',
                style: TextStyle(
                  color: Color(0xFF134E4A),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                code ?? '------',
                style: const TextStyle(
                  color: Color(0xFF0F766E),
                  fontSize: 28,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Temporary testing preview until the email sender is connected.',
                style: TextStyle(color: Color(0xFF0F766E), height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            counterText: '',
            labelText: '6-digit code',
            prefixIcon: Icon(Icons.pin_outlined),
          ),
          onSubmitted: (_) => onVerify(),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: isLoading ? null : onVerify,
          child: const Text('Verify Code'),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: isLoading ? null : onResend,
            child: const Text('Send a new code'),
          ),
        ),
      ],
    );
  }
}

class _PasswordStep extends StatelessWidget {
  const _PasswordStep({
    super.key,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.isLoading,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onCreateAccount,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool obscurePassword;
  final bool obscureConfirmPassword;
  final bool isLoading;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmPassword;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepIcon(icon: Icons.lock_person_outlined),
        const SizedBox(height: 22),
        const Text(
          'Secure your account',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Create a password you can remember. Type it twice so EFATA can confirm it matches.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: passwordController,
          obscureText: obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip: obscurePassword ? 'Show password' : 'Hide password',
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: onTogglePassword,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: confirmPasswordController,
          obscureText: obscureConfirmPassword,
          decoration: InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: const Icon(Icons.verified_user_outlined),
            suffixIcon: IconButton(
              tooltip: obscureConfirmPassword
                  ? 'Show password'
                  : 'Hide password',
              icon: Icon(
                obscureConfirmPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: onToggleConfirmPassword,
            ),
          ),
          onSubmitted: (_) => onCreateAccount(),
        ),
        const SizedBox(height: 18),
        const _InfoPanel(
          icon: Icons.shield_outlined,
          title: 'Next step',
          body:
              'After this, EFATA takes you straight into profile setup so your dashboard starts clean.',
        ),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: isLoading ? null : onCreateAccount,
          child: Text(isLoading ? 'Creating account...' : 'Create Account'),
        ),
      ],
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 31),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
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
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
