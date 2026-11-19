import 'package:flutter/material.dart';

import '../../../core/models/efata_api_models.dart';
import '../../../core/services/efata_api_client.dart';

class DriverEarningsSummary extends StatefulWidget {
  const DriverEarningsSummary({
    super.key,
    this.compact = false,
    this.onOpenDetails,
  });

  final bool compact;
  final VoidCallback? onOpenDetails;

  @override
  State<DriverEarningsSummary> createState() => _DriverEarningsSummaryState();
}

class _DriverEarningsSummaryState extends State<DriverEarningsSummary> {
  late Future<List<EfataOrder>> _orders = _load();

  Future<List<EfataOrder>> _load() =>
      EfataApiClient.instance.listAllOrders(status: 'completed');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FutureBuilder<List<EfataOrder>>(
      future: _orders,
      builder: (context, snapshot) {
        final jobs = snapshot.data ?? const <EfataOrder>[];
        final now = DateTime.now();
        final total = jobs.fold(0.0, (sum, job) => sum + job.amount);
        final monthly = jobs
            .where((job) {
              final date = job.completedAt?.toLocal();
              return date?.year == now.year && date?.month == now.month;
            })
            .fold(0.0, (sum, job) => sum + job.amount);
        final numberFormat = MaterialLocalizations.of(context);
        String money(double value) =>
            'NGN ${numberFormat.formatDecimal(value.round())}';
        return Card(
          color: widget.compact ? colors.primaryContainer : colors.surface,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: snapshot.hasError
                ? () => setState(() => _orders = _load())
                : widget.onOpenDetails,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delivery earnings',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          snapshot.hasData
                              ? money(total)
                              : snapshot.hasError
                              ? 'Unavailable'
                              : 'Loading...',
                          style: theme.textTheme.headlineSmall,
                        ),
                        if (snapshot.hasData) ...[
                          const SizedBox(height: 5),
                          Text(
                            '${jobs.length} completed  ·  ${money(monthly)} this month',
                          ),
                          if (!widget.compact) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Total for completed deliveries, before payout adjustments.',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ] else if (snapshot.hasError)
                          const Text('Tap to retry'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    snapshot.hasError
                        ? Icons.refresh
                        : widget.onOpenDetails != null
                        ? Icons.chevron_right
                        : Icons.account_balance_wallet_outlined,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
