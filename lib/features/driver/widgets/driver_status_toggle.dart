import 'package:flutter/material.dart';

class DriverStatusToggle extends StatelessWidget {
  final bool isOnline;
  final ValueChanged<bool> onChanged;

  const DriverStatusToggle({
    super.key,
    required this.isOnline,
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
        value: isOnline,
        onChanged: onChanged,
      ),
    );
  }
}