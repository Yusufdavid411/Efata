import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CustomerWelcomeHeader extends StatelessWidget {
  const CustomerWelcomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name == null || name.isEmpty ? 'Welcome back' : 'Welcome back, $name',
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          user?.email ?? '',
          style: const TextStyle(color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}
