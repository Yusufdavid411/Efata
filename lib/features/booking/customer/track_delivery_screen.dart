import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TrackDeliveryScreen extends StatelessWidget {
  final String orderId;

  const TrackDeliveryScreen({super.key, required this.orderId});

  String getStatusMessage(String status) {
    switch (status) {
      case 'pending':
        return 'Waiting for a driver to accept your request';
      case 'accepted':
        return 'Driver has accepted your delivery';
      case 'inTransit':
        return 'Your delivery is on the way';
      case 'completed':
        return 'Delivery completed successfully';
      case 'rejected':
        return 'Delivery request was rejected';
      default:
        return 'Processing...';
    }
  }

  double getProgressValue(String status) {
    switch (status) {
      case 'pending':
        return 0.2;
      case 'accepted':
        return 0.4;
      case 'inTransit':
        return 0.7;
      case 'completed':
        return 1.0;
      default:
        return 0.1;
    }
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'inTransit':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
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
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final order = snapshot.data!;
          final status = order['status'] ?? 'pending';

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),

                Icon(
                  Icons.local_shipping,
                  size: 80,
                  color: getStatusColor(status),
                ),

                const SizedBox(height: 20),

                Text(
                  getStatusMessage(status),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  "Status: $status",
                  style: const TextStyle(color: Colors.grey),
                ),

                const SizedBox(height: 20),

                LinearProgressIndicator(
                  value: getProgressValue(status),
                ),

                const SizedBox(height: 30),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _infoRow("Pickup", order['pickup']),
                        const SizedBox(height: 10),
                        _infoRow("Drop-off", order['dropoff']),
                        const SizedBox(height: 10),
                        _infoRow("Item", order['item']),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(value),
      ],
    );
  }
}