import 'package:flutter/material.dart';

import '../../core/services/app_notification_banner_service.dart';
import '../../core/services/password_strength_service.dart';
import '../../core/services/efata_session.dart';
import 'login_screen.dart';

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
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  int step = 0;
  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    passwordController.addListener(_refreshPasswordUi);
    confirmPasswordController.addListener(_refreshPasswordUi);
  }

  @override
  void dispose() {
    emailController.dispose();
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
    if (mounted && step == 1) setState(() {});
  }

  Future<void> sendCode() async {
    if (!_isValidEmail(email)) {
      AppNotificationBannerService.error(
        'Enter a valid email address to receive your EFATA code.',
        title: 'Check email',
      );
      return;
    }

    setState(() => step = 1);
  }

  Future<void> createAccount() async {
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;
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
      await EfataSession.instance.register(email, password, widget.role);
      if (!mounted) return;
      AppNotificationBannerService.success(
        'Confirm your email, then sign in to EFATA.',
        title: 'Check your email',
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (_) {
      if (mounted) {
        AppNotificationBannerService.error(
          'Registration failed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
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
          onPressed: isLoading ? null : goBackOneStep,
        ),
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
          children: [
            Row(
              children: List.generate(2, (index) {
                final active = index <= step;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 5,
                    margin: EdgeInsets.only(right: index == 1 ? 0 : 8),
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

                  onContinue: sendCode,
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
    required this.onContinue,
  });

  final String role;
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
          body: 'EFATA will email a confirmation link for this $role account.',
        ),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: isLoading ? null : onContinue,
          child: Text('Continue'),
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
              value: (result.score / 5).clamp(0.05, 1),
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 12),
          _RuleRow(
            passed: result.passedRules.contains(PasswordRule.length),
            label: 'At least 8 characters',
          ),
          _RuleRow(
            passed: result.passedRules.contains(PasswordRule.mixedCharacters),
            label: 'Mix letters with numbers, spaces, or symbols',
          ),
          _RuleRow(
            passed: result.passedRules.contains(PasswordRule.noObviousWords),
            label: 'Avoid using your email or phone number',
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
