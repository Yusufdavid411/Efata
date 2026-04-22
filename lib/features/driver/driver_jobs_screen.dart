import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logistics_app/core/services/order_service.dart';

class DriverJobsScreen extends StatelessWidget {
  const DriverJobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final OrderService orderService = OrderService();
    final currentDriver = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Jobs'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: orderService.getPendingOrders(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!.docs;

          if (orders.isEmpty) {
            return const Center(child: Text('No available jobs'));
          }

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];

              return Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Pickup: ${order['pickup']}"),
                      Text("Drop-off: ${order['dropoff']}"),
                      Text("Item: ${order['item']}"),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              await orderService.acceptOrder(
                                order.id,
                                currentDriver!.uid,
                              );
                            },
                            child: const Text("Accept"),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () async {
                              await orderService.rejectOrder(order.id);
                            },
                            child: const Text("Reject"),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}