import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:logistics_app/features/booking/customer/customer_home_screen.dart';
import 'package:logistics_app/features/booking/customer/customer_profile_screen.dart';
import 'package:logistics_app/features/booking/customer/order_history_screen.dart';
import 'package:logistics_app/features/booking/customer/simple_order_form.dart';
import 'package:logistics_app/features/auth/splash_screen.dart';
import 'package:logistics_app/features/driver/driver_home_screen.dart';
import 'package:logistics_app/features/driver/driver_profile_screen.dart';
import 'package:logistics_app/features/driver/driver_onboarding_screen.dart';
import 'package:logistics_app/features/driver/driver_jobs_screen.dart';
import 'package:logistics_app/features/auth/login_screen.dart';
import 'package:logistics_app/features/settings/settings_screen.dart';
import 'package:logistics_app/core/controllers/app_settings_controller.dart';
import 'package:logistics_app/core/services/chat_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await appSettingsController.loadSettings();
  await ChatNotificationService.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData lightTheme() {
    const seed = Color(0xFF0F766E);

    return ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: seed),
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF5F7FB),
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: seed, width: 1.6),
        ),
        labelStyle: const TextStyle(color: Color(0xFF475569)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  ThemeData darkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2DD4BF),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        foregroundColor: Color(0xFFF8FAFC),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF111827),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            '/': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
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
