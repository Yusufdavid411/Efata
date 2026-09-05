import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../../shared/widgets/ai_floating_button.dart';
import 'widgets/customer_welcome_header.dart';
import 'widgets/customer_summary_card.dart';
import 'widgets/customer_primary_action.dart';
import 'widgets/active_delivery_section.dart';
import 'simple_order_form.dart';

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(isDriver: false),
      appBar: AppBar(title: const Text("Customer Dashboard")),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                const CustomerWelcomeHeader(),
                const SizedBox(height: 20),
                const _CustomerSetupCard(),
                const SizedBox(height: 20),
                const CustomerSummaryCard(),
                const SizedBox(height: 20),
                CustomerPrimaryAction(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SimpleOrderForm(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                const ActiveDeliverySection(),
                const SizedBox(height: 20),
              ],
            ),
          ),
          const AIFloatingButton(),
        ],
      ),
    );
  }
}

class _CustomerSetupCard extends StatelessWidget {
  const _CustomerSetupCard();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final profileCompleted = data?['profileCompleted'] == true;

        if (profileCompleted) return const SizedBox.shrink();

        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.pushNamed(context, '/customerOnboarding'),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.assignment_outlined,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Complete customer profile',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Add your phone and main pickup address for smoother deliveries.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
