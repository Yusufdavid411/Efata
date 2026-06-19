import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverHistorySection extends StatelessWidget {
  const DriverHistorySection({super.key});

  String formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return "${d.day}/${d.month}/${d.year}  ${d.hour}:${d.minute}";
  }

  @override
  Widget build(BuildContext context) {
    final driver = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: driver?.uid)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        final docs = snapshot.data!.docs;

        final current = docs.where((d) {
          final s = d['status'];
          return s == 'accepted' || s == 'inTransit';
        }).toList();

        final completed = docs.where((d) {
          return d['status'] == 'completed';
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (current.isNotEmpty) ...[
              const Text(
                "Current Job",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ...current.map((job) {
                final data = job.data() as Map<String, dynamic>;
                return Card(
                  child: ListTile(
                    title: Text("${data['pickup']} -> ${data['dropoff']}"),
                    subtitle: Text("Status: ${data['status']}"),
                  ),
                );
              }),
              const SizedBox(height: 20),
            ],

            const Text(
              "Recent Jobs",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            if (completed.isEmpty) const Text("No completed jobs yet"),

            ...completed.map((job) {
              final data = job.data() as Map<String, dynamic>;
              return Card(
                child: ListTile(
                  title: Text("${data['pickup']} -> ${data['dropoff']}"),
                  subtitle: Text(
                    "Completed: ${formatTime(data['completedAt'])}",
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
