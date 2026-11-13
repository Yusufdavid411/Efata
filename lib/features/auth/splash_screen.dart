import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/account_access_service.dart';
import '../../core/services/auth_service.dart';
import '../booking/customer/customer_home_screen.dart';
import '../driver/driver_home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _loginTimer;

  @override
  void initState() {
    super.initState();
    _loginTimer = Timer(const Duration(seconds: 2), checkLogin);
  }

  Future<void> checkLogin() async {
    final authService = AuthService();
    final user = authService.currentUser;

    if (!mounted) return;

    if (user != null) {
      final access = await AccountAccessService().loadCurrent();
      if (access == null || access.isBlocked) {
        await authService.logout();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }
      if (!mounted) return;
      if (access.role == 'customer') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CustomerHomeScreen()),
        );
      } else if (access.role == 'driver') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _loginTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF5F7FB),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF0F766E),
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
              child: SizedBox(
                width: 88,
                height: 88,
                child: Icon(
                  Icons.local_shipping_rounded,
                  size: 46,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 22),
            Text(
              'EFATA',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Move goods with confidence',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            SizedBox(height: 30),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
