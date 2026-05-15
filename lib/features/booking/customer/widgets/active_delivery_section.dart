import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../tracking/track_delivery_screen.dart';

class ActiveDeliverySection extends StatelessWidget {
  const ActiveDeliverySection({super.key});

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
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('customerId', isEqualTo: user?.uid)
          .where('status', whereIn: ['pending', 'accepted', 'inTransit'])
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox();
        }

        final order = snapshot.data!.docs.first;
        final data = order.data() as Map<String, dynamic>;

        final pickup = data['pickup']?.toString() ?? 'No pickup';
        final dropoff = data['dropoff']?.toString() ?? 'No drop-off';
        final status = data['status']?.toString() ?? 'pending';
        final vehicleType = data['vehicleType']?.toString();
        final statusText = vehicleType == null || vehicleType.isEmpty
            ? 'Status: ${_formatStatus(status)}'
            : 'Status: ${_formatStatus(status)} - $vehicleType';

        return Card(
          color: Colors.blue.shade50,
          child: ListTile(
            title: Text('$pickup -> $dropoff'),
            subtitle: Text(statusText),
            trailing: ElevatedButton(
              child: const Text('Track'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TrackDeliveryScreen(orderId: order.id),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
