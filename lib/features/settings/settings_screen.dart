import 'package:flutter/material.dart';
import '../../core/controllers/app_settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String themeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return "Light Mode";
      case ThemeMode.dark:
        return "Dark Mode";
      case ThemeMode.system:
        return "System Default";
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettingsController,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("Settings"),
            centerTitle: true,
          ),
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
                    RadioListTile<ThemeMode>(
                      title: const Text("System Default"),
                      subtitle: const Text("Follow your device appearance"),
                      value: ThemeMode.system,
                      groupValue: appSettingsController.themeMode,
                      onChanged: (value) {
                        if (value != null) {
                          appSettingsController.updateThemeMode(value);
                        }
                      },
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text("Light Mode"),
                      value: ThemeMode.light,
                      groupValue: appSettingsController.themeMode,
                      onChanged: (value) {
                        if (value != null) {
                          appSettingsController.updateThemeMode(value);
                        }
                      },
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text("Dark Mode"),
                      value: ThemeMode.dark,
                      groupValue: appSettingsController.themeMode,
                      onChanged: (value) {
                        if (value != null) {
                          appSettingsController.updateThemeMode(value);
                        }
                      },
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
              const Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.notifications_outlined),
                      title: Text("Notifications"),
                      subtitle: Text("Coming soon"),
                    ),
                    ListTile(
                      leading: Icon(Icons.language_outlined),
                      title: Text("Language"),
                      subtitle: Text("English"),
                    ),
                    ListTile(
                      leading: Icon(Icons.help_outline),
                      title: Text("Help & Support"),
                      subtitle: Text("Coming soon"),
                    ),
                    ListTile(
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