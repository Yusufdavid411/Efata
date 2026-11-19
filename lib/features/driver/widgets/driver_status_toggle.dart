import 'package:flutter/material.dart';

class DriverStatusToggle extends StatelessWidget {
  const DriverStatusToggle({
    super.key,
    required this.isOnline,
    required this.canGoOnline,
    this.isLoading = false,
    required this.onChanged,
  });

  final bool isOnline;
  final bool canGoOnline;
  final bool isLoading;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: isOnline ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOnline ? 'Online' : 'Offline',
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    isOnline ? 'Receiving requests' : 'Requests paused',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isLoading)
              const SizedBox.square(
                dimension: 44,
                child: Padding(
                  padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (isOnline)
              OutlinedButton(
                onPressed: () => onChanged(false),
                child: const Text('Go offline'),
              )
            else
              FilledButton(
                onPressed: canGoOnline ? () => onChanged(true) : null,
                child: const Text('Go online'),
              ),
          ],
        ),
      ),
    );
  }
}
