import 'package:flutter/material.dart';

import 'registration_flow_screen.dart';

class DriverRegisterScreen extends StatelessWidget {
  const DriverRegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RegistrationFlowScreen(
      role: 'driver',
      title: 'Driver registration',
      subtitle:
          'Enter your email so EFATA can confirm your driver account before profile setup.',
      onboardingRoute: '/driverOnboarding',
    );
  }
}
