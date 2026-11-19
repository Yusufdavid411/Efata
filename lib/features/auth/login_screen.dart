import 'package:flutter/material.dart';
import 'package:logistics_app/core/services/app_notification_banner_service.dart';
import 'package:logistics_app/core/services/efata_api_client.dart';
import 'package:logistics_app/core/services/efata_session.dart';

import '../../core/services/account_access_service.dart';
import 'role_selection_screen.dart';
import 'google_sign_in_button.dart';
import 'auth_heading.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> loginUser() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      AppNotificationBannerService.error(
        'Please enter email and password.',
        title: 'Missing login details',
      );
      return;
    }

    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      await EfataSession.instance.signIn(email, password);
      final account = await EfataApiClient.instance.bootstrapAccount();
      final access = AccountAccess.fromApi(account);
      if (access.isBlocked || !['customer', 'driver'].contains(access.role)) {
        throw const EfataApiException('account_unavailable', statusCode: 403);
      }
      EfataSession.instance.accountUid = account.uid;
      if (mounted) Navigator.pushReplacementNamed(context, access.homeRoute);
    } on EfataApiException catch (error) {
      EfataSession.instance.clear();
      if (!mounted) return;
      if (error.code == 'sign_in_cancelled') return;
      AppNotificationBannerService.error(switch (error.code) {
        'invalid_credentials' => 'Incorrect email or password.',
        'email_not_confirmed' => 'Confirm your email before signing in.',
        'account_unavailable' =>
          'This account is unavailable. Contact support.',
        _ => 'EFATA sign-in is unavailable for this account.',
      }, title: 'Login failed');
    } catch (e) {
      EfataSession.instance.clear();
      if (!mounted) return;

      AppNotificationBannerService.error(
        'Sign-in was interrupted. Please try again.',
        title: 'Login failed',
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AuthHeading(
                title: 'Sign in',
                subtitle:
                    'Book deliveries, track trips, and manage your EFATA account.',
              ),
              const SizedBox(height: 24),
              GoogleSignInButton(
                enabled: !isLoading,
                onBusyChanged: (busy) => setState(() => isLoading = busy),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or sign in with email'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
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
                          onPressed: isLoading ? null : loginUser,
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
            ],
          ),
        ),
      ),
    );
  }
}
