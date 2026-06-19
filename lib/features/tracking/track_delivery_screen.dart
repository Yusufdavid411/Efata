import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../chat/chat_screen.dart';
import '../../shared/widgets/app_live_map.dart';

class TrackDeliveryScreen extends StatelessWidget {
  final String orderId;

  const TrackDeliveryScreen({super.key, required this.orderId});

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  String _formatStatus(String status) {
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
        return status;
    }
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'Not available';
    if (price is num) return 'NGN ${price.toStringAsFixed(0)}';

    final parsed = double.tryParse(price.toString());
    if (parsed == null) return price.toString();

    return 'NGN ${parsed.toStringAsFixed(0)}';
  }

  String _formatPaymentStatus(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return 'Paid';
      case 'customersent':
        return 'Customer Sent';
      case 'cashdue':
        return 'Cash Due';
      case 'pending':
        return 'Pending';
      case 'failed':
        return 'Failed';
      default:
        return status;
    }
  }

  bool _canMarkPaymentSent(String status, String paymentStatus) {
    final orderActive = [
      'accepted',
      'intransit',
      'completed',
    ].contains(status.toLowerCase());
    final paymentOpen = [
      'pending',
      'cashdue',
    ].contains(paymentStatus.toLowerCase());

    return orderActive && paymentOpen;
  }

  bool _canCancelOrder(String status) {
    return status.toLowerCase() == 'pending';
  }

  Future<void> _markPaymentSent(
    BuildContext context,
    String paymentMethod,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Text(
          paymentMethod == 'Cash on Delivery'
              ? 'Confirm that you will pay the driver directly when the delivery is completed.'
              : 'Confirm that you have sent or started this payment outside the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final status = paymentMethod == 'Cash on Delivery'
        ? 'cashDue'
        : 'customerSent';

    await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
      'paymentStatus': status,
      'paymentCustomerConfirmedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Payment status updated')));
  }

  Future<void> _cancelPendingOrder(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Delivery?'),
        content: const Text(
          'This will cancel the delivery request before any driver accepts it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Request'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel Delivery'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
      'status': 'canceled',
      'canceledAt': FieldValue.serverTimestamp(),
      'canceledBy': 'customer',
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Delivery request canceled')));
  }

  int _progressIndex(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 0;
      case 'accepted':
        return 1;
      case 'intransit':
        return 2;
      case 'completed':
        return 3;
      case 'rejected':
      case 'canceled':
      case 'cancelled':
        return -1;
      default:
        return 0;
    }
  }

  String _progressMessage(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Waiting for an available driver to accept this delivery.';
      case 'accepted':
        return 'A driver has accepted the job and is preparing for pickup.';
      case 'intransit':
        return 'Your goods are moving toward the drop-off location.';
      case 'completed':
        return 'Delivery has been completed and confirmed.';
      case 'rejected':
        return 'This request was rejected. Please create another delivery.';
      case 'canceled':
      case 'cancelled':
        return 'This delivery request was canceled before assignment.';
      default:
        return 'Tracking information will update as the delivery progresses.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Track Delivery'), centerTitle: true),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Order not found'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final pickupLat = _toDouble(data['pickupLat']);
          final pickupLng = _toDouble(data['pickupLng']);
          final dropoffLat = _toDouble(data['dropoffLat']);
          final dropoffLng = _toDouble(data['dropoffLng']);
          final driverLat = _toDouble(data['driverLat']);
          final driverLng = _toDouble(data['driverLng']);

          final status = data['status']?.toString() ?? 'pending';
          final paymentMethod =
              data['paymentMethod']?.toString() ?? 'Cash on Delivery';
          final paymentStatus = data['paymentStatus']?.toString() ?? 'pending';
          final price = data['price'];
          final isCompleted = status.toLowerCase() == 'completed';
          final summary = _TrackingSummary(
            status: _formatStatus(status),
            message: _progressMessage(status),
            progressIndex: _progressIndex(status),
            amount: _formatPrice(price),
            payment: '$paymentMethod - ${_formatPaymentStatus(paymentStatus)}',
            hasDriverLocation: driverLat != null && driverLng != null,
            isCompleted: isCompleted,
            onChat: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ChatScreen(orderId: orderId, participantRole: 'customer'),
                ),
              );
            },
            onPaymentTap: _canMarkPaymentSent(status, paymentStatus)
                ? () => _markPaymentSent(context, paymentMethod)
                : null,
            onCancelTap: _canCancelOrder(status)
                ? () => _cancelPendingOrder(context)
                : null,
          );

          if (pickupLat == null ||
              pickupLng == null ||
              dropoffLat == null ||
              dropoffLng == null) {
            return Column(
              children: [
                summary,
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Map location is not available for this order, but delivery progress will keep updating here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          final pickupPoint = LatLng(pickupLat, pickupLng);
          final dropoffPoint = LatLng(dropoffLat, dropoffLng);

          final driverPoint = driverLat != null && driverLng != null
              ? LatLng(driverLat, driverLng)
              : null;

          return Column(
            children: [
              summary,
              Expanded(
                child: AppLiveMap(
                  pickupPoint: pickupPoint,
                  dropoffPoint: dropoffPoint,
                  driverPoint: driverPoint,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrackingSummary extends StatelessWidget {
  const _TrackingSummary({
    required this.status,
    required this.message,
    required this.progressIndex,
    required this.amount,
    required this.payment,
    required this.hasDriverLocation,
    required this.isCompleted,
    required this.onChat,
    required this.onPaymentTap,
    required this.onCancelTap,
  });

  final String status;
  final String message;
  final int progressIndex;
  final String amount;
  final String payment;
  final bool hasDriverLocation;
  final bool isCompleted;
  final VoidCallback onChat;
  final VoidCallback? onPaymentTap;
  final VoidCallback? onCancelTap;

  @override
  Widget build(BuildContext context) {
    final steps = const [
      ('Requested', Icons.receipt_long_outlined),
      ('Accepted', Icons.verified_outlined),
      ('In Transit', Icons.local_shipping_outlined),
      ('Delivered', Icons.check_circle_outline),
    ];
    final statusColor = progressIndex < 0
        ? Colors.red
        : isCompleted
        ? Colors.green
        : Colors.blue;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: statusColor.shade50,
        border: Border(bottom: BorderSide(color: statusColor.shade100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Status: $status',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                hasDriverLocation
                    ? Icons.gps_fixed_rounded
                    : Icons.timeline_rounded,
                color: statusColor.shade700,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(message, style: const TextStyle(color: Color(0xFF475569))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailPill(label: 'Amount', value: amount),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DetailPill(label: 'Payment', value: payment),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Chat'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onPaymentTap,
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(
                    onPaymentTap == null ? 'Payment Updated' : 'Payment Sent',
                  ),
                ),
              ),
            ],
          ),
          if (onCancelTap != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onCancelTap,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel Pending Request'),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: _ProgressStep(
                    label: steps[i].$1,
                    icon: steps[i].$2,
                    isActive: progressIndex >= i,
                    isCurrent: progressIndex == i,
                  ),
                ),
                if (i != steps.length - 1)
                  Container(
                    width: 18,
                    height: 2,
                    color: progressIndex > i
                        ? statusColor.shade500
                        : const Color(0xFFCBD5E1),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.isCurrent,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF0F766E) : const Color(0xFF94A3B8);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFDDFCF3) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isCurrent ? const Color(0xFF0F766E) : color,
              width: isCurrent ? 2 : 1,
            ),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
