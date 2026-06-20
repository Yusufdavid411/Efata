import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DriverHistorySection extends StatelessWidget {
  const DriverHistorySection({
    super.key,
    this.showHeader = true,
    this.maxItems,
  });

  final bool showHeader;
  final int? maxItems;

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return 'Date not available';

    final date = timestamp.toDate();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '${date.day}/${date.month}/${date.year}  $hour:$minute';
  }

  String _formatPrice(dynamic price) {
    if (price is num) return 'NGN ${price.toStringAsFixed(0)}';

    final parsed = double.tryParse(price?.toString() ?? '');
    if (parsed != null) return 'NGN ${parsed.toStringAsFixed(0)}';

    return 'Price not set';
  }

  int _sortTime(QueryDocumentSnapshot job) {
    final data = job.data() as Map<String, dynamic>;
    for (final key in ['completedAt', 'updatedAt', 'createdAt']) {
      final value = data[key];
      if (value is Timestamp) return value.millisecondsSinceEpoch;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: driver.uid)
          .snapshots(),
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
            message: snapshot.error.toString(),
            tone: Colors.red,
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final completed = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['status']?.toString().toLowerCase() == 'completed';
        }).toList();

        completed.sort((a, b) => _sortTime(b).compareTo(_sortTime(a)));

        final visibleJobs = maxItems == null
            ? completed
            : completed.take(maxItems!).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
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
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (visibleJobs.isEmpty)
              const _HistoryStateCard(
                icon: Icons.work_history_outlined,
                title: 'No recent jobs yet',
                message: 'Completed deliveries will appear here.',
              )
            else
              ...visibleJobs.map((job) {
                final data = job.data() as Map<String, dynamic>;
                return _RecentJobCard(
                  pickup: data['pickup']?.toString() ?? 'Pickup location',
                  dropoff: data['dropoff']?.toString() ?? 'Drop-off location',
                  completedAt: _formatTime(data['completedAt'] as Timestamp?),
                  price: _formatPrice(data['price']),
                  vehicleType: data['vehicleType']?.toString(),
                );
              }),
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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFFDF6),
                    borderRadius: BorderRadius.circular(12),
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
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Icon(
                          Icons.arrow_downward_rounded,
                          color: Color(0xFF94A3B8),
                          size: 17,
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
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaPill(
                  icon: Icons.event_available_outlined,
                  label: completedAt,
                ),
                _MetaPill(icon: Icons.payments_outlined, label: price),
                if (vehicleType != null && vehicleType!.isNotEmpty)
                  _MetaPill(
                    icon: Icons.local_shipping_outlined,
                    label: vehicleType!,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w800,
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
