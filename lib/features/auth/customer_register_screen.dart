import 'package:flutter/material.dart';

import 'registration_flow_screen.dart';

class CustomerRegisterScreen extends StatelessWidget {
  const CustomerRegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RegistrationFlowScreen(
      role: 'customer',
      title: 'Customer Registration',
      subtitle:
          'Enter your email so EFATA can confirm your account before you book deliveries.',
      onboardingRoute: '/customerOnboarding',
    );
  }
}
