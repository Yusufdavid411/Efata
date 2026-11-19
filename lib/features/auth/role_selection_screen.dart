import 'package:flutter/material.dart';

import 'customer_register_screen.dart';
import 'driver_register_screen.dart';
import 'auth_heading.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const AuthHeading(
              title: 'Choose your account',
              subtitle: 'Are you sending goods or delivering them?',
            ),
            const SizedBox(height: 24),
            _RoleCard(
              icon: Icons.inventory_2_outlined,
              title: 'Passenger',
              subtitle: 'Book transport, track trips, and manage deliveries.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CustomerRegisterScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            _RoleCard(
              icon: Icons.local_shipping_outlined,
              title: 'Driver',
              subtitle: 'Receive jobs, manage availability, and earn payouts.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DriverRegisterScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        onTap: onTap,
        leading: Icon(icon, color: colors.primary, size: 26),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
