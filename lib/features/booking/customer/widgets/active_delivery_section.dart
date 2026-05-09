import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../tracking/track_delivery_screen.dart';

class ActiveDeliverySection extends StatelessWidget {
  const ActiveDeliverySection({super.key});

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

        return Card(
          color: Colors.blue.shade50,
          child: ListTile(
            title: Text('$pickup → $dropoff'),
            subtitle: Text('Status: $status'),
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