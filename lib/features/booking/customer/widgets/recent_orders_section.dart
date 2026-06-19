import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
          children: orders.map((order) {
            return ListTile(
              title: Text("${order['pickup']} -> ${order['dropoff']}"),
              subtitle: Text(order['status']),
            );
          }).toList(),
        );
      },
    );
  }
}
