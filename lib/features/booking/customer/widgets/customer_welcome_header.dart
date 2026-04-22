import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CustomerWelcomeHeader extends StatelessWidget {
  const CustomerWelcomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Welcome 👋",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(user?.email ?? ""),
      ],
    );
  }
}