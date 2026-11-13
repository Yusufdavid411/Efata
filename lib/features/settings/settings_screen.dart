import 'package:flutter/material.dart';
import '../../core/services/efata_api_client.dart';
import '../../core/controllers/app_settings_controller.dart';
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
              const SizedBox(height: 20),
              const Text(
                "Account",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const _AccountActionsCard(),
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

class _AccountActionsCard extends StatefulWidget {
  const _AccountActionsCard();

  @override
  State<_AccountActionsCard> createState() => _AccountActionsCardState();
}

class _AccountActionsCardState extends State<_AccountActionsCard> {
  bool isLoggingOut = false;

  Future<void> confirmLogout() async {
    final role = await _currentRole();
    if (!mounted) return;

    final body = role == 'driver'
        ? 'You will stop receiving delivery requests after logging out.'
        : 'You will need to sign in again before booking or tracking deliveries.';

    final shouldLogout = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Log out of EFATA?',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 20,
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
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Logout'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('Stay Logged In'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldLogout != true) return;

    setState(() => isLoggingOut = true);
    try {
      await AuthService().logout();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    } finally {
      if (mounted) setState(() => isLoggingOut = false);
    }
  }

  Future<String> _currentRole() async {
    try {
      return (await EfataApiClient.instance.getMe()).role;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
        ),
        title: const Text(
          'Logout',
          style: TextStyle(
            color: Color(0xFFDC2626),
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: const Text('Sign out on this device'),
        trailing: isLoggingOut
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: isLoggingOut ? null : confirmLogout,
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
