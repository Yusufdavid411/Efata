import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'widgets/active_delivery_section.dart';

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  bool isCurrentOrder(QueryDocumentSnapshot order) {
    final data = order.data() as Map<String, dynamic>;
    final status = data['status']?.toString() ?? '';
    return status == 'pending' || status == 'accepted' || status == 'inTransit';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('customerId', isEqualTo: currentUser?.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }

          final orders = snapshot.data?.docs ?? [];

          if (orders.isEmpty) {
            return const Center(child: Text('No orders yet'));
          }

          final currentOrders = orders.where(isCurrentOrder).toList();
          final previousOrders = orders
              .where((order) => !isCurrentOrder(order))
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (currentOrders.isNotEmpty) ...[
                const _SectionTitle(title: 'Current order'),
                ...currentOrders.map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OrderPreviewCard(
                      order: order,
                      title: currentOrders.first == order ? 'Active now' : null,
                      isPrimary: currentOrders.first == order,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (previousOrders.isNotEmpty) ...[
                const _SectionTitle(title: 'Previous orders'),
                ...previousOrders.map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OrderPreviewCard(order: order),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
