import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logistics_app/features/booking/customer/track_delivery_screen.dart';

// ✅ IMPORT TRACK SCREEN
import '../../tracking/track_delivery_screen.dart';

class RecentOrdersSection extends StatelessWidget {
  const RecentOrdersSection({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('customerId', isEqualTo: user?.uid)
          .orderBy('createdAt', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        final orders = snapshot.data!.docs;

        if (orders.isEmpty) {
          return const Text("No recent orders");
        }

        return Column(
          children: orders.map((doc) {
            final order = doc.data() as Map<String, dynamic>;
            final orderId = doc.id;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text("${order['pickup']} → ${order['dropoff']}"),

                subtitle: Text("Status: ${order['status']}"),

                // ✅ TRACK BUTTON ADDED HERE
                trailing: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TrackDeliveryScreen(orderId: orderId),
                      ),
                    );
                  },
                  child: const Text("Track"),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}