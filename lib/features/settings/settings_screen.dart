import 'package:flutter/material.dart';
import '../../core/controllers/app_settings_controller.dart';
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
