import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:logistics_app/features/booking/customer/customer_home_screen.dart';
import 'package:logistics_app/features/booking/customer/customer_profile_screen.dart';
import 'package:logistics_app/features/booking/customer/order_history_screen.dart';
import 'package:logistics_app/features/booking/customer/simple_order_form.dart';
import 'package:logistics_app/features/driver/driver_home_screen.dart';
import 'package:logistics_app/features/driver/driver_profile_screen.dart';
import 'package:logistics_app/features/driver/driver_onboarding_screen.dart';
import 'package:logistics_app/features/auth/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
      },
    );
  }
}
