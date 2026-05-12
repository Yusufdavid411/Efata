import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/widgets/app_live_map.dart';

class TrackDeliveryScreen extends StatelessWidget {
  final String orderId;

  const TrackDeliveryScreen({
    super.key,
    required this.orderId,
  });

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Delivery'),
        centerTitle: true,
      ),
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
                color: Colors.blue.shade50,
                child: Text(
                  'Status: ${_formatStatus(status)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
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