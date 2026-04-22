import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/order_service.dart';

class AvailableJobsSection extends StatelessWidget {
  final bool isOnline;

  const AvailableJobsSection({super.key, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    if (!isOnline) {
      return const SizedBox();
    }

    final orderService = OrderService();
    final driver = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: orderService.getPendingOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const CircularProgressIndicator();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Text("No available jobs");
        }

        final jobs = snapshot.data!.docs;

        return Column(
          children: jobs.map((job) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title:
                    Text("${job['pickup']} → ${job['dropoff']}"),
                subtitle: const Text("Pending"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        await orderService.acceptOrder(
                            job.id, driver!.uid);
                      },
                      child: const Text("Accept"),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await orderService.rejectOrder(job.id);
                      },
                      child: const Text("Reject"),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}