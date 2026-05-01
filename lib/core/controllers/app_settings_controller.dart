import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsController extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.light;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('themeMode') ?? 'light';

    if (savedTheme == 'dark') {
      themeMode = ThemeMode.dark;
    } else {
      themeMode = ThemeMode.light;
    }

    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    themeMode = mode;

    final prefs = await SharedPreferences.getInstance();

    if (mode == ThemeMode.dark) {
      await prefs.setString('themeMode', 'dark');
    } else {
      await prefs.setString('themeMode', 'light');
    }

    notifyListeners();
  }
}

final appSettingsController = AppSettingsController();