import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:logistics_app/features/booking/customer/customer_home_screen.dart';
import 'package:logistics_app/features/booking/customer/customer_profile_screen.dart';
import 'package:logistics_app/features/booking/customer/order_history_screen.dart';
import 'package:logistics_app/features/booking/customer/simple_order_form.dart';
import 'package:logistics_app/features/driver/driver_home_screen.dart';
import 'package:logistics_app/features/driver/driver_profile_screen.dart';
import 'package:logistics_app/features/driver/driver_onboarding_screen.dart';
import 'package:logistics_app/features/driver/driver_jobs_screen.dart';
import 'package:logistics_app/features/auth/login_screen.dart';
import 'package:logistics_app/features/settings/settings_screen.dart';
import 'package:logistics_app/core/controllers/app_settings_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await appSettingsController.loadSettings();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData lightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      primarySwatch: Colors.deepPurple,
      scaffoldBackgroundColor: Colors.grey.shade100,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
    );
  }

  ThemeData darkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      primarySwatch: Colors.deepPurple,
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFF1E1E1E),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettingsController,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: lightTheme(),
          darkTheme: darkTheme(),
          themeMode: appSettingsController.themeMode,
          initialRoute: '/',
          routes: {
            '/': (context) => const LoginScreen(),
            '/customerHome': (context) => const CustomerHomeScreen(),
            '/driverHome': (context) => const DriverHomeScreen(),
            '/orders': (context) => const OrderHistoryScreen(),
            '/createOrder': (context) => const SimpleOrderForm(),
            '/customerProfile': (context) => const CustomerProfileScreen(),
            '/driverProfile': (context) => const DriverProfileScreen(),
            '/driverOnboarding': (context) => const DriverOnboardingScreen(),
            '/driverJobs': (context) => const DriverJobsScreen(),
            '/settings': (context) => const SettingsScreen(),
          },
        );
      },
    );
  }
}