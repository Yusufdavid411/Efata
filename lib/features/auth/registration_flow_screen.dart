import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/app_notification_banner_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/email_registration_service.dart';
import '../../core/services/password_strength_service.dart';

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
  final registrationService = EmailRegistrationService.instance;
  final authService = AuthService();

  int step = 0;
  bool isLoading = false;
  bool isGoogleLoading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  String? verifiedCode;

  @override
  void initState() {
    super.initState();
    passwordController.addListener(_refreshPasswordUi);
    confirmPasswordController.addListener(_refreshPasswordUi);
  }

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

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  void _refreshPasswordUi() {
    if (mounted && step == 2) setState(() {});
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
      await registrationService.sendRegistrationCode(
        email: email,
        role: widget.role,
      );

      if (!mounted) return;
      setState(() {
        codeController.clear();
        verifiedCode = null;
        step = 1;
      });

      AppNotificationBannerService.success(
        'We sent a 6-digit EFATA code to $email.',
        title: 'Check your email',
      );
    } on EmailRegistrationException catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(e.message, title: 'Check email');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> verifyCode() async {
    final code = codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      AppNotificationBannerService.error(
        'Enter the 6-digit EFATA code from your email.',
        title: 'Check code',
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      await registrationService.verifyRegistrationCode(
        email: email,
        role: widget.role,
        code: code,
      );

      if (!mounted) return;
      setState(() {
        verifiedCode = code;
        step = 2;
      });
      AppNotificationBannerService.success(
        'Email confirmed. Create a secure password.',
        title: 'Email verified',
      );
    } on EmailRegistrationException catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(e.message, title: 'Code failed');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> createAccount() async {
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;
    final code = verifiedCode ?? codeController.text.trim();
    final strength = PasswordStrengthService.evaluate(
      password: password,
      confirmPassword: confirmPassword,
      email: email,
    );

    if (!strength.isAcceptable) {
      AppNotificationBannerService.error(
        strength.feedback.first,
        title: 'Strengthen password',
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      await registrationService.completeRegistration(
        email: email,
        role: widget.role,
        code: code,
        password: password,
      );

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

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
    } on EmailRegistrationException catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        e.message,
        title: 'Registration failed',
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        e.message ?? 'Account created, but sign-in failed. Please log in.',
        title: 'Sign-in failed',
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> continueWithGoogle() async {
    setState(() => isGoogleLoading = true);

    try {
      await FirebaseAuth.instance.signOut();
      final credential = await authService.signInWithGoogle();
      final user = credential.user;
      if (user == null) throw Exception('Google sign-in failed.');

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final userDoc = await userRef.get();
      final existingRole = userDoc.data()?['role']?.toString();

      if (existingRole != null &&
          existingRole.isNotEmpty &&
          existingRole != widget.role) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        AppNotificationBannerService.error(
          'This Google account is already registered as $existingRole.',
          title: 'Account already exists',
        );
        return;
      }

      await authService.createGoogleProfileIfNeeded(
        user: user,
        role: widget.role,
      );

      final route = await _routeForGoogleUser(user.uid, widget.role);
      if (!mounted) return;
      AppNotificationBannerService.success(
        'Google account connected. Continue your EFATA setup.',
        title: 'Welcome',
      );
      Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'missing-google-web-client-id' =>
          'Add the Firebase Web Client ID to this build before Google sign-in can work.',
        'account-exists-with-different-credential' =>
          'This email already uses password login. Sign in with password, then add Google in Settings.',
        _ => e.message ?? 'Google sign-in failed. Please try again.',
      };
      AppNotificationBannerService.error(
        message,
        title: 'Google sign-up failed',
      );
    } catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        e.toString(),
        title: 'Google sign-up failed',
      );
    } finally {
      if (mounted) setState(() => isGoogleLoading = false);
    }
  }

  Future<String> _routeForGoogleUser(String uid, String role) async {
    if (role == 'driver') {
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .get();
      return driverDoc.data()?['profileCompleted'] == true
          ? '/driverHome'
          : '/driverOnboarding';
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    return userDoc.data()?['profileCompleted'] == true
        ? '/customerHome'
        : '/customerOnboarding';
  }

  Future<void> goBackOneStep() async {
    if (step == 0) {
      Navigator.pop(context);
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
          onPressed: isLoading || isGoogleLoading ? null : goBackOneStep,
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
                  role: widget.role,
                  subtitle: widget.subtitle,
                  controller: emailController,
                  isLoading: isLoading,
                  isGoogleLoading: isGoogleLoading,
                  onContinue: sendCode,
                  onGoogle: continueWithGoogle,
                ),
                1 => _CodeStep(
                  key: const ValueKey('code'),
                  email: email,
                  controller: codeController,
                  isLoading: isLoading,
                  onVerify: verifyCode,
                  onResend: sendCode,
                ),
                _ => _PasswordStep(
                  key: const ValueKey('password'),
                  email: email,
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
    required this.role,
    required this.subtitle,
    required this.controller,
    required this.isLoading,
    required this.isGoogleLoading,
    required this.onContinue,
    required this.onGoogle,
  });

  final String role;
  final String subtitle;
  final TextEditingController controller;
  final bool isLoading;
  final bool isGoogleLoading;
  final VoidCallback onContinue;
  final VoidCallback onGoogle;

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
        _GoogleAccountButton(
          isLoading: isGoogleLoading,
          label: 'Continue with Google',
          onPressed: isLoading || isGoogleLoading ? null : onGoogle,
        ),
        const SizedBox(height: 18),
        const _DividerLabel(label: 'or use email code'),
        const SizedBox(height: 18),
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
              'EFATA will send a secure 6-digit code to verify this $role account.',
        ),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: isLoading || isGoogleLoading ? null : onContinue,
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
    required this.controller,
    required this.isLoading,
    required this.onVerify,
    required this.onResend,
  });

  final String email;
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
          'We sent an EFATA verification code to $email.',
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        const _InfoPanel(
          icon: Icons.mail_lock_outlined,
          title: 'Check your inbox',
          body:
              'Enter the 6-digit code from EFATA. The code expires after 10 minutes.',
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
          child: Text(isLoading ? 'Checking code...' : 'Verify Code'),
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
    required this.email,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.isLoading,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onCreateAccount,
  });

  final String email;
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
    final strength = PasswordStrengthService.evaluate(
      password: passwordController.text,
      confirmPassword: confirmPasswordController.text,
      email: email,
    );

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
          'Use a strong passphrase. EFATA checks strength and confirms both passwords match before continuing.',
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
        _PasswordStrengthPanel(result: strength),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: isLoading || !strength.isAcceptable
              ? null
              : onCreateAccount,
          child: Text(isLoading ? 'Creating account...' : 'Create Account'),
        ),
      ],
    );
  }
}

class _PasswordStrengthPanel extends StatelessWidget {
  const _PasswordStrengthPanel({required this.result});

  final PasswordStrengthResult result;

  @override
  Widget build(BuildContext context) {
    final color = switch (result.score) {
      <= 2 => const Color(0xFFDC2626),
      3 || 4 => const Color(0xFFD97706),
      5 => const Color(0xFF0F766E),
      _ => const Color(0xFF16A34A),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Password strength: ${result.label}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
              Icon(
                result.isAcceptable
                    ? Icons.check_circle_rounded
                    : Icons.shield_outlined,
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: (result.score / 6).clamp(0.05, 1),
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 12),
          _RuleRow(
            passed: result.passedRules.contains(PasswordRule.length),
            label: 'At least 12 characters',
          ),
          _RuleRow(
            passed: result.passedRules.contains(PasswordRule.passphrase),
            label: '15+ characters recommended',
          ),
          _RuleRow(
            passed: result.passedRules.contains(PasswordRule.mixedCharacters),
            label: 'Mix letters with numbers, spaces, or symbols',
          ),
          _RuleRow(
            passed: result.passedRules.contains(PasswordRule.noObviousWords),
            label: 'Avoid common words, EFATA, or your email name',
          ),
          _RuleRow(
            passed: result.passedRules.contains(PasswordRule.passwordsMatch),
            label: 'Passwords match',
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.passed, required this.label});

  final bool passed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: passed ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: passed
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleAccountButton extends StatelessWidget {
  const _GoogleAccountButton({
    required this.isLoading,
    required this.label,
    required this.onPressed,
  });

  final bool isLoading;
  final String label;
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
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'G',
                    style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
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
