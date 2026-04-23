import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  String formatPrice(dynamic price) {
    if (price == null) return "Price not available";

    if (price is num) {
      return "₦${price.toStringAsFixed(0)}";
    }

    final parsed = double.tryParse(price.toString());
    if (parsed != null) {
      return "₦${parsed.toStringAsFixed(0)}";
    }

    return "Price not available";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Jobs'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Something went wrong\n${snapshot.error}'),
            );
          }

          final jobs = snapshot.data?.docs ?? [];

          jobs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;

            final aTime =
                (aData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bTime =
                (bData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

            return bTime.compareTo(aTime);
          });

          if (jobs.isEmpty) {
            return const Center(
              child: Text(
                "No available jobs right now",
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              final data = job.data() as Map<String, dynamic>;

              final pickup =
                  data['pickup']?.toString() ?? 'No pickup location';
              final dropoff =
                  data['dropoff']?.toString() ?? 'No drop-off location';
              final item =
                  data['item']?.toString() ?? 'No item description';
              final price = data['price'];

              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$pickup → $dropoff",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text("Item: $item"),
                      const SizedBox(height: 8),
                      Text(
                        formatPrice(price),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
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