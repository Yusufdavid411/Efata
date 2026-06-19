import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../tracking/track_delivery_screen.dart';

class ActiveDeliverySection extends StatelessWidget {
  const ActiveDeliverySection({super.key});

  bool isCurrentOrder(String status) {
    return status == 'pending' || status == 'accepted' || status == 'inTransit';
  }

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
        final previous = orders.skip(1).take(2).toList();

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
                  onPressed: () {
                    Navigator.pushNamed(context, '/orders');
                  },
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
                  ? 'Latest current order'
                  : 'Latest order',
              isPrimary: true,
            ),
            if (previous.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Previous orders',
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              ...previous.map(
                (order) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OrderPreviewCard(order: order),
                ),
              ),
            ],
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

  String formatStatus(String status) {
    switch (status.toLowerCase()) {
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

  Color statusColor(String status) {
    switch (status.toLowerCase()) {
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

  bool isCurrentOrder(String status) {
    return status == 'pending' || status == 'accepted' || status == 'inTransit';
  }

  @override
  Widget build(BuildContext context) {
    final data = order.data() as Map<String, dynamic>;
    final pickup = data['pickup']?.toString() ?? 'No pickup';
    final dropoff = data['dropoff']?.toString() ?? 'No drop-off';
    final status = data['status']?.toString() ?? 'unknown';
    final vehicleType = data['vehicleType']?.toString();
    final price = (data['price'] as num?)?.toDouble();
    final unreadMessages = (data['unreadForCustomer'] as num?)?.toInt() ?? 0;
    final current = isCurrentOrder(status);

    return Card(
      color: isPrimary ? const Color(0xFFEFFDF6) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
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
            Text(
              '$pickup -> $dropoff',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(label: formatStatus(status), color: statusColor(status)),
                if (vehicleType != null && vehicleType.isNotEmpty)
                  _Pill(label: vehicleType, color: const Color(0xFF0F766E)),
                if (price != null)
                  _Pill(
                    label: 'NGN ${price.toStringAsFixed(0)}',
                    color: const Color(0xFF334155),
                  ),
                if (unreadMessages > 0)
                  _Pill(
                    label: unreadMessages > 9
                        ? '9+ new messages'
                        : '$unreadMessages new messages',
                    color: const Color(0xFFDC2626),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: current
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                TrackDeliveryScreen(orderId: order.id),
                          ),
                        );
                      }
                    : null,
                child: Text(current ? 'View Order' : 'Ended'),
              ),
            ),
          ],
        ),
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
