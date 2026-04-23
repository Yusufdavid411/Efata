import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverHistorySection extends StatelessWidget {
  const DriverHistorySection({super.key});

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
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) {
      return const Text("Driver not logged in");
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: driver.uid)
          .where('status', isEqualTo: 'completed')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Text("Something went wrong: ${snapshot.error}");
        }

        final history = snapshot.data?.docs ?? [];

        history.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;

          final aTime =
              (aData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final bTime =
              (bData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

          return bTime.compareTo(aTime);
        });

        if (history.isEmpty) {
          return const Text("No completed jobs yet");
        }

        return Column(
          children: history.map((job) {
            final data = job.data() as Map<String, dynamic>;

            final pickup =
                data['pickup']?.toString() ?? 'No pickup location';
            final dropoff =
                data['dropoff']?.toString() ?? 'No drop-off location';
            final price = data['price'];

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text("$pickup → $dropoff"),
                subtitle: const Text("Completed"),
                trailing: Text(
                  formatPrice(price),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}