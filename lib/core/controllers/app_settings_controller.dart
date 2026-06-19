import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsController extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.light;
  bool orderNotificationsEnabled = true;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('themeMode') ?? 'light';
    orderNotificationsEnabled =
        prefs.getBool('orderNotificationsEnabled') ?? true;

    switch (savedTheme) {
      case 'dark':
        themeMode = ThemeMode.dark;
        break;
      case 'system':
        themeMode = ThemeMode.system;
        break;
      case 'light':
      default:
        themeMode = ThemeMode.light;
    }

    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    themeMode = mode;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('themeMode', mode.name);

    notifyListeners();
  }

  Future<void> updateOrderNotifications(bool enabled) async {
    orderNotificationsEnabled = enabled;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('orderNotificationsEnabled', enabled);

    notifyListeners();
  }
}

final appSettingsController = AppSettingsController();
