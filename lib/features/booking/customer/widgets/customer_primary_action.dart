import 'package:flutter/material.dart';

class CustomerPrimaryAction extends StatelessWidget {
  final VoidCallback onPressed;

  const CustomerPrimaryAction({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(16),
        ),
        onPressed: onPressed,
        child: const Text(
          "Create Transport Request",
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}