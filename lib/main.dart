import 'package:flutter/material.dart';
import 'package:logistics_app/features/booking/customer/customer_home_screen.dart';
import 'package:logistics_app/features/booking/customer/customer_onboarding_screen.dart';
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
import 'package:logistics_app/core/services/app_notification_banner_service.dart';
import 'package:logistics_app/core/services/chat_notification_service.dart';
import 'package:logistics_app/core/services/voice_navigation_control_service.dart';
import 'shared/theme/efata_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await VoiceNavigationControlService.stopStaleGuidanceOnFreshLaunch();
  await appSettingsController.loadSettings();
  await ChatNotificationService.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettingsController,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: AppNotificationBannerService.navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: EfataTheme.build(Brightness.light),
          darkTheme: EfataTheme.build(Brightness.dark),
          themeMode: appSettingsController.themeMode,
          initialRoute: '/',
          onGenerateRoute: (settings) {
            final uri = Uri.tryParse(settings.name ?? '');
            if (uri?.scheme == 'efata' && uri?.host == 'login') {
              return MaterialPageRoute(builder: (_) => const LoginScreen());
            }
            return null;
          },
          routes: {
            '/': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
            '/customerHome': (context) => const CustomerHomeScreen(),
            '/customerOnboarding': (context) =>
                const CustomerOnboardingScreen(),
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
