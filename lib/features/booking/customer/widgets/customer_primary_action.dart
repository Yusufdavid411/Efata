import 'package:flutter/material.dart';

class CustomerPrimaryAction extends StatelessWidget {
  final VoidCallback onPressed;

  const CustomerPrimaryAction({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.primary,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: colors.onPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Send goods now',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onPrimary,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward, color: colors.onPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
