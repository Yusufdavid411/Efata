import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../track_delivery_screen.dart';

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

        return Card(
          color: Colors.blue.shade50,
          child: ListTile(
            title: Text("${order['pickup']} → ${order['dropoff']}"),
            subtitle: Text("Status: ${order['status']}"),
            trailing: ElevatedButton(
              child: const Text("Track"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        TrackDeliveryScreen(orderId: order.id),
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