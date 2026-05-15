import 'package:flutter/material.dart';

import 'customer_register_screen.dart';
import 'driver_register_screen.dart';

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
            const Text(
              'How will you use EFATA?',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 28,
                height: 1.08,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose one account type. You can manage your profile after registration.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            _RoleCard(
              icon: Icons.inventory_2_outlined,
              title: 'Send goods',
              subtitle: 'Book transport, track trips, and manage deliveries.',
              actionLabel: 'Continue as Customer',
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
              title: 'Deliver goods',
              subtitle: 'Receive jobs, manage availability, and earn payouts.',
              actionLabel: 'Continue as Driver',
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
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: colors.primary, size: 28),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      actionLabel,
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, color: colors.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
