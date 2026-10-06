import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/services/google_route_service.dart';
import '../../../tracking/track_delivery_screen.dart';

class ActiveDeliverySection extends StatelessWidget {
  const ActiveDeliverySection({super.key});

  bool isCurrentOrder(String status) => _isCurrentOrder(status);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('customerId', isEqualTo: user?.uid)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = snapshot.data?.docs ?? [];

        if (orders.isEmpty) {
          return const _EmptyOrdersCard();
        }

        final latest = orders.first;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Your orders',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/orders'),
                  child: const Text('See more'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OrderPreviewCard(
              order: latest,
              title:
                  isCurrentOrder(
                    ((latest.data() as Map<String, dynamic>)['status'] ?? '')
                        .toString(),
                  )
                  ? 'Active delivery'
                  : 'Most recent delivery',
              isPrimary: true,
            ),
          ],
        );
      },
    );
  }
}

class OrderPreviewCard extends StatelessWidget {
  const OrderPreviewCard({
    super.key,
    required this.order,
    this.title,
    this.isPrimary = false,
  });

  final QueryDocumentSnapshot order;
  final String? title;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final data = order.data() as Map<String, dynamic>;
    final pickup = data['pickup']?.toString() ?? 'No pickup';
    final dropoff = data['dropoff']?.toString() ?? 'No drop-off';
    final status = data['status']?.toString() ?? 'unknown';
    final unreadMessages = (data['unreadForCustomer'] as num?)?.toInt() ?? 0;
    final current = _isCurrentOrder(status);
    final normalizedStatus = _normalizeStatus(status);

    return Card(
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (current) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TrackDeliveryScreen(orderId: order.id),
              ),
            );
            return;
          }
          _showOrderDetails(context, data);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: FutureBuilder<String?>(
            future: _tripTime(data),
            builder: (context, etaSnapshot) {
              final eta = etaSnapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFFDF6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          current
                              ? Icons.route_rounded
                              : Icons.check_circle_outline_rounded,
                          color: const Color(0xFF0F766E),
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
                            Text(
                              eta == null
                                  ? _formatStatus(status)
                                  : '${_formatStatus(status)} . about $eta',
                              style: TextStyle(
                                color: _statusColor(normalizedStatus),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                  if (unreadMessages > 0) ...[
                    const SizedBox(height: 10),
                    _Pill(
                      label: unreadMessages > 9
                          ? '9+ new messages'
                          : '$unreadMessages new messages',
                      color: const Color(0xFFDC2626),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showOrderDetails(BuildContext context, Map<String, dynamic> data) {
    final pickup = data['pickup']?.toString() ?? 'No pickup';
    final dropoff = data['dropoff']?.toString() ?? 'No drop-off';
    final status = data['status']?.toString() ?? 'unknown';
    final vehicleType = data['vehicleType']?.toString();
    final price = (data['price'] as num?)?.toDouble();

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
                  'Order details',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                _DetailRow(label: 'Status', value: _formatStatus(status)),
                _DetailRow(label: 'Pickup', value: pickup),
                _DetailRow(label: 'Drop-off', value: dropoff),
                if (vehicleType != null && vehicleType.isNotEmpty)
                  _DetailRow(label: 'Vehicle', value: vehicleType),
                if (price != null)
                  _DetailRow(
                    label: 'Amount',
                    value: 'NGN ${price.toStringAsFixed(0)}',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

bool _isCurrentOrder(String status) {
  final normalized = _normalizeStatus(status);
  return normalized == 'pending' ||
      normalized == 'accepted' ||
      normalized == 'intransit';
}

String _normalizeStatus(String status) {
  return status.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
}

String _formatStatus(String status) {
  switch (_normalizeStatus(status)) {
    case 'intransit':
      return 'In Transit';
    case 'accepted':
      return 'Accepted';
    case 'pending':
      return 'Pending';
    case 'completed':
      return 'Completed';
    case 'rejected':
      return 'Rejected';
    case 'canceled':
    case 'cancelled':
      return 'Canceled';
    default:
      return status.isEmpty ? 'Unknown' : status;
  }
}

Color _statusColor(String status) {
  switch (_normalizeStatus(status)) {
    case 'pending':
      return const Color(0xFFD97706);
    case 'accepted':
      return const Color(0xFF2563EB);
    case 'intransit':
      return const Color(0xFF7C3AED);
    case 'completed':
      return const Color(0xFF16A34A);
    case 'rejected':
    case 'canceled':
    case 'cancelled':
      return const Color(0xFFDC2626);
    default:
      return const Color(0xFF64748B);
  }
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

String _formatDuration(int minutes) {
  if (minutes <= 0) return 'time unavailable';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  final hourLabel = hours == 1 ? '1hr' : '${hours}hrs';
  return remainder == 0 ? hourLabel : '$hourLabel ${remainder}min';
}

Future<String?> _tripTime(Map<String, dynamic> data) async {
  final pickupLat = _toDouble(data['pickupLat']);
  final pickupLng = _toDouble(data['pickupLng']);
  final dropoffLat = _toDouble(data['dropoffLat']);
  final dropoffLng = _toDouble(data['dropoffLng']);
  if (pickupLat == null ||
      pickupLng == null ||
      dropoffLat == null ||
      dropoffLng == null) {
    return null;
  }

  final route = await GoogleRouteService.routeBetween(
    pickup: LatLng(pickupLat, pickupLng),
    dropoff: LatLng(dropoffLat, dropoffLng),
    cachePrecision: 4,
  );
  if (route == null) return null;
  return _formatDuration(route.durationMinutes);
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
            width: 86,
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

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyOrdersCard extends StatelessWidget {
  const _EmptyOrdersCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 34,
            ),
            const SizedBox(height: 10),
            const Text(
              'No orders yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Create your first delivery request to see it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}
