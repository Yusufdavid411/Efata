import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
          return const _CustomerSummaryLoading();
        }

        final orders = snapshot.data!.docs;
        int active = 0;
        int completed = 0;
        int pending = 0;
        int issues = 0;

        for (final order in orders) {
          final data = order.data() as Map<String, dynamic>;
          final status = data['status']?.toString();
          if (status == 'completed') completed++;
          if (status == 'pending') pending++;
          if (status == 'accepted' || status == 'inTransit') active++;
          if (data['needsAdminReview'] == true) issues++;
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 22,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDFA),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.dashboard_customize_outlined,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delivery Command Center',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Track what needs attention today.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _summaryItem(
                    Icons.route_outlined,
                    'Active',
                    active,
                    const Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 10),
                  _summaryItem(
                    Icons.schedule_outlined,
                    'Pending',
                    pending,
                    const Color(0xFFD97706),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _summaryItem(
                    Icons.check_circle_outline_rounded,
                    'Completed',
                    completed,
                    const Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 10),
                  _summaryItem(
                    Icons.support_agent_outlined,
                    'Reviews',
                    issues,
                    const Color(0xFF7C3AED),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summaryItem(IconData icon, String title, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.toString(),
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 21,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerSummaryLoading extends StatelessWidget {
  const _CustomerSummaryLoading();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: const [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Loading delivery overview',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
