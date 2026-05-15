import 'package:flutter/material.dart';

class DriverStatusToggle extends StatelessWidget {
  final bool isOnline;
  final bool isLoading;
  final ValueChanged<bool> onChanged;

  const DriverStatusToggle({
    super.key,
    required this.isOnline,
    this.isLoading = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        title: Text(
          isOnline ? 'You are Online' : 'You are Offline',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          isOnline
              ? 'Available to receive delivery requests'
              : 'Not receiving new delivery requests',
        ),
        value: isOnline,
        onChanged: isLoading ? null : onChanged,
      ),
    );
  }
}
