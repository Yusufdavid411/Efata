import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

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
      default:
        return status;
    }
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'Not available';
    if (price is num) return '₦${price.toStringAsFixed(0)}';

    final parsed = double.tryParse(price.toString());
    if (parsed == null) return price.toString();

    return '₦${parsed.toStringAsFixed(0)}';
  }

  String _formatPaymentStatus(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return 'Paid';
      case 'pending':
        return 'Pending';
      case 'failed':
        return 'Failed';
      default:
        return status;
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

          if (pickupLat == null ||
              pickupLng == null ||
              dropoffLat == null ||
              dropoffLng == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Location data is missing. Please create the order using the map picker.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final pickupPoint = LatLng(pickupLat, pickupLng);
          final dropoffPoint = LatLng(dropoffLat, dropoffLng);

          final driverPoint = driverLat != null && driverLng != null
              ? LatLng(driverLat, driverLng)
              : null;

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                color: isCompleted ? Colors.green.shade50 : Colors.blue.shade50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status: ${_formatStatus(status)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text('Amount: ${_formatPrice(price)}'),
                    const SizedBox(height: 4),
                    Text(
                      'Payment: $paymentMethod - ${_formatPaymentStatus(paymentStatus)}',
                    ),
                    if (isCompleted) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Delivery completed successfully.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
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
