import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/controllers/app_settings_controller.dart';
import '../../core/services/app_notification_banner_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/chat_notification_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettingsController,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text("Settings"), centerTitle: true),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                "Appearance",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    _ThemeOption(
                      title: const Text("System Default"),
                      subtitle: const Text("Follow your device appearance"),
                      mode: ThemeMode.system,
                    ),
                    _ThemeOption(
                      title: const Text("Light Mode"),
                      mode: ThemeMode.light,
                    ),
                    _ThemeOption(
                      title: const Text("Dark Mode"),
                      mode: ThemeMode.dark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Password & sign-in",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const _PasswordSigninCard(),
              const SizedBox(height: 20),
              const Text(
                "Preferences",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_outlined),
                      title: const Text("Order notifications"),
                      subtitle: const Text("Show delivery and payment updates"),
                      value: appSettingsController.orderNotificationsEnabled,
                      onChanged: (enabled) async {
                        if (enabled) {
                          await ChatNotificationService.instance
                              .requestPhonePermission();
                        }
                        await appSettingsController.updateOrderNotifications(
                          enabled,
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.mark_chat_unread_outlined),
                      title: const Text("Test chat notification"),
                      subtitle: const Text("Confirm alerts work on this phone"),
                      onTap: () async {
                        await ChatNotificationService.instance
                            .requestPhonePermission();
                        await ChatNotificationService.instance
                            .showTestNotification();
                      },
                    ),
                    const ListTile(
                      leading: Icon(Icons.language_outlined),
                      title: Text("Language"),
                      subtitle: Text("English"),
                    ),
                    const ListTile(
                      leading: Icon(Icons.help_outline),
                      title: Text("Help & Support"),
                      subtitle: Text("Contact admin from delivery chat"),
                    ),
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text("App Version"),
                      subtitle: Text("1.0.0"),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PasswordSigninCard extends StatefulWidget {
  const _PasswordSigninCard();

  @override
  State<_PasswordSigninCard> createState() => _PasswordSigninCardState();
}

class _PasswordSigninCardState extends State<_PasswordSigninCard> {
  final authService = AuthService();
  bool isSending = false;
  bool isLinkingGoogle = false;

  Future<void> sendSetupEmail() async {
    setState(() => isSending = true);
    try {
      await authService.sendPasswordSetupEmail();
      if (!mounted) return;
      AppNotificationBannerService.success(
        'We sent a secure password setup link to your email.',
        title: 'Check your email',
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        e.message ?? 'Password setup email could not be sent.',
        title: 'Password setup failed',
      );
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  Future<void> linkGoogle() async {
    setState(() => isLinkingGoogle = true);
    try {
      await authService.linkCurrentUserWithGoogle();
      if (!mounted) return;
      AppNotificationBannerService.success(
        'You can now sign in with Google or your password.',
        title: 'Google connected',
      );
      setState(() {});
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'missing-google-web-client-id' =>
          'Add the Firebase Web Client ID to this build before Google sign-in can work.',
        'provider-already-linked' => 'Google is already connected.',
        'credential-already-in-use' =>
          'This Google account is already connected to another EFATA account.',
        'google-email-mismatch' =>
          e.message ??
              'Choose the same Google email as this EFATA account to link them.',
        _ => e.message ?? 'Google could not be connected.',
      };
      AppNotificationBannerService.error(message, title: 'Google link failed');
    } finally {
      if (mounted) setState(() => isLinkingGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final providers = user?.providerData.map((p) => p.providerId).toSet() ?? {};
    final hasPassword = providers.contains('password');
    final hasGoogle = providers.contains('google.com');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.admin_panel_settings_outlined,
                color: Color(0xFF0F766E),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasPassword
                        ? 'Password login active'
                        : 'Create password login',
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasPassword
                        ? hasGoogle
                              ? 'This account can sign in with Google or password.'
                              : 'This account signs in with email and password.'
                        : 'Use this if you created your account with Google and also want password login later.',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                  if (!hasPassword) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: isSending ? null : sendSetupEmail,
                      icon: const Icon(Icons.mark_email_read_outlined),
                      label: Text(
                        isSending ? 'Sending...' : 'Send setup email',
                      ),
                    ),
                  ],
                  if (hasPassword && !hasGoogle) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: isLinkingGoogle ? null : linkGoogle,
                      icon: const Text(
                        'G',
                        style: TextStyle(
                          color: Color(0xFF4285F4),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      label: Text(
                        isLinkingGoogle
                            ? 'Connecting...'
                            : 'Connect Google sign-in',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.title, required this.mode, this.subtitle});

  final Widget title;
  final Widget? subtitle;
  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final selected = appSettingsController.themeMode == mode;

    return ListTile(
      title: title,
      subtitle: subtitle,
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      onTap: () => appSettingsController.updateThemeMode(mode),
    );
  }
}
