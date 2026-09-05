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
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Delivery Overview',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    summaryItem(
                      context,
                      Icons.route_outlined,
                      "Active",
                      active,
                      const Color(0xFF0F766E),
                    ),
                    const SizedBox(width: 10),
                    summaryItem(
                      context,
                      Icons.schedule_outlined,
                      "Pending",
                      pending,
                      const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 10),
                    summaryItem(
                      context,
                      Icons.check_circle_outline_rounded,
                      "Completed",
                      completed,
                      const Color(0xFF16A34A),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget summaryItem(
    BuildContext context,
    IconData icon,
    String title,
    int value,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 8),
            Text(
              value.toString(),
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
