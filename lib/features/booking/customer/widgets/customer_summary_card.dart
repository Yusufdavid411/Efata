import 'package:flutter/material.dart';

import '../../../../core/models/efata_api_models.dart';
import '../../../../core/services/efata_api_client.dart';

class CustomerSummaryCard extends StatelessWidget {
  const CustomerSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ApiCustomerSummaryCard();
  }
}

class _ApiCustomerSummaryCard extends StatefulWidget {
  const _ApiCustomerSummaryCard();

  @override
  State<_ApiCustomerSummaryCard> createState() =>
      _ApiCustomerSummaryCardState();
}

class _ApiCustomerSummaryCardState extends State<_ApiCustomerSummaryCard> {
  late Future<List<EfataOrder>> _orders;

  @override
  void initState() {
    super.initState();
    _orders = EfataApiClient.instance.listAllOrders();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EfataOrder>>(
      future: _orders,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _CustomerSummaryLoading();
        }
        if (snapshot.hasError) {
          return _CustomerSummaryError(
            onRetry: () => setState(
              () => _orders = EfataApiClient.instance.listAllOrders(),
            ),
          );
        }

        var active = 0;
        var pending = 0;
        var completed = 0;
        for (final order in snapshot.data ?? const <EfataOrder>[]) {
          switch (_normalizeStatus(order.status)) {
            case 'pending':
              pending++;
            case 'accepted':
            case 'intransit':
              active++;
            case 'completed':
              completed++;
          }
        }

        return _SummaryContent(
          active: active,
          pending: pending,
          completed: completed,
        );
      },
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({
    required this.active,
    required this.pending,
    required this.completed,
  });

  final int active;
  final int pending;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Delivery overview', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final metric in [
                  ('Active', active),
                  ('Pending', pending),
                  ('Delivered', completed),
                ])
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${metric.$2}',
                          style: theme.textTheme.headlineSmall,
                        ),
                        Text(
                          metric.$1,
                          style: TextStyle(color: colors.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _normalizeStatus(String status) =>
    status.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

class _CustomerSummaryError extends StatelessWidget {
  const _CustomerSummaryError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.cloud_off_outlined),
      title: const Text('Delivery overview unavailable'),
      trailing: IconButton(
        tooltip: 'Retry delivery overview',
        icon: const Icon(Icons.refresh),
        onPressed: onRetry,
      ),
    ),
  );
}

class _CustomerSummaryLoading extends StatelessWidget {
  const _CustomerSummaryLoading();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: const [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Loading delivery overview',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
