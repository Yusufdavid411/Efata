import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CustomerSummaryCard extends StatelessWidget {
  const CustomerSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('customerId', isEqualTo: user?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox();
        }

        final orders = snapshot.data!.docs;

        int active = 0;
        int completed = 0;
        int pending = 0;

        for (var order in orders) {
          final status = order['status'];
          if (status == 'completed') completed++;
          if (status == 'pending') pending++;
          if (status == 'accepted' || status == 'inTransit') active++;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                summaryItem("Active", active),
                summaryItem("Pending", pending),
                summaryItem("Completed", completed),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget summaryItem(String title, int value) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(title),
      ],
    );
  }
}