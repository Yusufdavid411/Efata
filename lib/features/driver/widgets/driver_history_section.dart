import 'package:flutter/material.dart';

import '../../../core/models/efata_api_models.dart';
import '../../../core/services/efata_api_client.dart';

class DriverHistorySection extends StatelessWidget {
  const DriverHistorySection({
    super.key,
    this.showHeader = true,
    this.maxItems,
  });

  final bool showHeader;
  final int? maxItems;

  @override
  Widget build(BuildContext context) {
    return _ApiDriverHistorySection(showHeader: showHeader, maxItems: maxItems);
  }
}

class _ApiDriverHistorySection extends StatefulWidget {
  const _ApiDriverHistorySection({
    required this.showHeader,
    required this.maxItems,
  });

  final bool showHeader;
  final int? maxItems;

  @override
  State<_ApiDriverHistorySection> createState() =>
      _ApiDriverHistorySectionState();
}

class _ApiDriverHistorySectionState extends State<_ApiDriverHistorySection> {
  late Future<List<EfataOrder>> _orders;

  @override
  void initState() {
    super.initState();
    _orders = EfataApiClient.instance.listAllOrders(status: 'completed');
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Date not available';
    final date = value.toLocal();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year}  $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EfataOrder>>(
      future: _orders,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _HistoryStateCard(
            icon: Icons.sync_rounded,
            title: 'Loading recent jobs',
            message: 'Checking completed deliveries for this driver account.',
            isLoading: true,
          );
        }
        if (snapshot.hasError) {
          return _HistoryStateCard(
            icon: Icons.error_outline_rounded,
            title: 'Recent jobs could not load',
            message: 'Check your connection and try again.',
            tone: Colors.red,
          );
        }

        final completed = [...snapshot.data ?? const <EfataOrder>[]]
          ..sort((a, b) {
            final aTime = a.completedAt ?? a.updatedAt ?? a.createdAt;
            final bTime = b.completedAt ?? b.updatedAt ?? b.createdAt;
            return (bTime ?? DateTime(1970)).compareTo(aTime ?? DateTime(1970));
          });
        final visible = widget.maxItems == null
            ? completed
            : completed.take(widget.maxItems!).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showHeader) ...[
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Recent Jobs',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (completed.isNotEmpty)
                    Text(
                      '${completed.length} completed',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (widget.maxItems != null &&
                      completed.length > widget.maxItems!) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/driverJobs'),
                      child: const Text('See more'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (visible.isEmpty)
              const _HistoryStateCard(
                icon: Icons.work_history_outlined,
                title: 'No recent jobs yet',
                message: 'Completed deliveries will appear here.',
              )
            else
              ...visible.map(
                (order) => _RecentJobCard(
                  pickup: order.pickup,
                  dropoff: order.dropoff,
                  completedAt: _formatDate(order.completedAt),
                  price: 'NGN ${order.amount.toStringAsFixed(0)}',
                  vehicleType: order.vehicleType,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RecentJobCard extends StatelessWidget {
  const _RecentJobCard({
    required this.pickup,
    required this.dropoff,
    required this.completedAt,
    required this.price,
    this.vehicleType,
  });

  final String pickup;
  final String dropoff;
  final String completedAt;
  final String price;
  final String? vehicleType;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFFDF6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dropoff,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'From $pickup',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Completed delivery',
                      style: TextStyle(
                        color: Color(0xFF0F766E),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Job details',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                _DetailRow(label: 'Pickup', value: pickup),
                _DetailRow(label: 'Drop-off', value: dropoff),
                _DetailRow(label: 'Completed', value: completedAt),
                _DetailRow(label: 'Amount', value: price),
                if (vehicleType != null && vehicleType!.isNotEmpty)
                  _DetailRow(label: 'Vehicle', value: vehicleType!),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryStateCard extends StatelessWidget {
  const _HistoryStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.tone = const Color(0xFF0F766E),
    this.isLoading = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color tone;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Icon(icon, color: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
