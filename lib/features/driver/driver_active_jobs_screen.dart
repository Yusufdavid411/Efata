import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logistics_app/core/services/order_service.dart';

class DriverActiveJobsScreen extends StatelessWidget {
  const DriverActiveJobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final driver = FirebaseAuth.instance.currentUser;
    final OrderService orderService = OrderService();

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Active Jobs"),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: orderService.getDriverOrders(driver!.uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final jobs = snapshot.data!.docs;

          if (jobs.isEmpty) {
            return const Center(child: Text("No active jobs"));
          }

          return ListView.builder(
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              final status = job['status'];

              return Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Pickup: ${job['pickup']}"),
                      Text("Drop-off: ${job['dropoff']}"),
                      Text("Status: ${status.toString().toUpperCase()}"),
                      const SizedBox(height: 10),

                      if (status == 'accepted')
                        ElevatedButton(
                          onPressed: () {
                            orderService.startTransit(job.id);
                          },
                          child: const Text("Start Transit"),
                        ),

                      if (status == 'inTransit')
                        ElevatedButton(
                          onPressed: () {
                            orderService.completeOrder(job.id);
                          },
                          child: const Text("Mark Completed"),
                        ),
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