import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TrackDeliveryScreen extends StatelessWidget {
  final String orderId;

  const TrackDeliveryScreen({
    super.key,
    required this.orderId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Track Delivery')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final order = snapshot.data!;
          final status = order['status'];

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Pickup: ${order['pickup']}"),
                Text("Drop-off: ${order['dropoff']}"),
                Text("Item: ${order['item']}"),
                const SizedBox(height: 30),

                const Text(
                  "Delivery Status",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),

                StatusIndicator(status: status),
              ],
            ),
          );
        },
      ),
    );
  }
}

class StatusIndicator extends StatelessWidget {
  final String status;

  const StatusIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (status) {
      case 'pending':
        color = Colors.orange;
        label = "Waiting for driver";
        break;
      case 'accepted':
        color = Colors.blue;
        label = "Driver assigned";
        break;
      case 'inTransit':
        color = Colors.purple;
        label = "In transit";
        break;
      case 'completed':
        color = Colors.green;
        label = "Completed";
        break;
      case 'rejected':
        color = Colors.red;
        label = "Rejected";
        break;
      default:
        color = Colors.grey;
        label = status;
    }

    return Row(
      children: [
        Icon(Icons.circle, color: color, size: 14),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}