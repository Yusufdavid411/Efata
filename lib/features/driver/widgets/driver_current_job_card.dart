import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/efata_api_models.dart';
import '../../../core/services/efata_api_client.dart';
import '../driver_active_jobs_screen.dart';

class DriverCurrentJobCard extends StatelessWidget {
  const DriverCurrentJobCard({super.key, this.showEmptyState = false});

  final bool showEmptyState;

  @override
  Widget build(BuildContext context) {
    return _ApiCurrentJobCard(showEmptyState: showEmptyState);
  }
}

class _ApiCurrentJobCard extends StatefulWidget {
  const _ApiCurrentJobCard({required this.showEmptyState});

  final bool showEmptyState;

  @override
  State<_ApiCurrentJobCard> createState() => _ApiCurrentJobCardState();
}

class _ApiCurrentJobCardState extends State<_ApiCurrentJobCard> {
  Timer? _timer;
  EfataOrder? _order;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final page = await EfataApiClient.instance.listOrders();
      final active =
          page.orders.where((order) {
            final status = order.status.toLowerCase().replaceAll(
              RegExp(r'[\s_-]+'),
              '',
            );
            return status == 'accepted' || status == 'intransit';
          }).toList()..sort((a, b) {
            final aTime =
                a.startedAt ?? a.acceptedAt ?? a.updatedAt ?? a.createdAt;
            final bTime =
                b.startedAt ?? b.acceptedAt ?? b.updatedAt ?? b.createdAt;
            return (bTime ?? DateTime(1970)).compareTo(aTime ?? DateTime(1970));
          });
      if (!mounted) return;
      setState(() {
        _order = active.isEmpty ? null : active.first;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return widget.showEmptyState
          ? const _CurrentJobStateCard(
              icon: Icons.sync_rounded,
              title: 'Checking current job',
              message: 'Your active delivery will appear here.',
              isLoading: true,
            )
          : const SizedBox.shrink();
    }
    final order = _order;
    if (order == null) {
      return widget.showEmptyState
          ? const _CurrentJobStateCard(
              icon: Icons.local_shipping_outlined,
              title: 'No current job',
              message:
                  'Accepted and in-transit deliveries will show here when assigned.',
            )
          : const SizedBox.shrink();
    }
    return _CurrentJobDetailsCard(
      orderId: order.id,
      data: order.toLegacyMap(),
      status: _formatApiStatus(order.status),
    );
  }
}

String _formatApiStatus(String status) {
  final normalized = status.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  return normalized == 'intransit' ? 'In Transit' : 'Accepted';
}

class _CurrentJobDetailsCard extends StatelessWidget {
  const _CurrentJobDetailsCard({
    required this.orderId,
    required this.data,
    required this.status,
  });

  final String orderId;
  final Map<String, dynamic> data;
  final String status;

  @override
  Widget build(BuildContext context) {
    final pickup = data['pickup']?.toString() ?? 'Pickup location';
    final dropoff = data['dropoff']?.toString() ?? 'Drop-off location';
    final vehicleType = data['vehicleType']?.toString();

    void openJob() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverActiveJobsScreen(initialOrderId: orderId),
        ),
      );
    }

    return Card(
      color: const Color(0xFFEFF8FF),
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFBFDBFE)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: openJob,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.route_rounded, color: Color(0xFF0F766E)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Current Job',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _StatusPill(label: status),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                pickup,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Icon(
                  Icons.arrow_downward_rounded,
                  color: Color(0xFF64748B),
                  size: 20,
                ),
              ),
              Text(
                dropoff,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              if (vehicleType != null && vehicleType.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.local_shipping_outlined,
                      size: 18,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      vehicleType,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: openJob,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('View Job'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF166534),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CurrentJobStateCard extends StatelessWidget {
  const _CurrentJobStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.isLoading = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
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
                : Icon(icon, color: const Color(0xFF0F766E)),
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
