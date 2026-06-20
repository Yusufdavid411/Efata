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

  String formatStatus(dynamic status) {
    switch (status?.toString().toLowerCase()) {
      case 'accepted':
        return 'Accepted';
      case 'intransit':
        return 'In Transit';
      case 'completed':
        return 'Completed';
      case 'pending':
        return 'Pending';
      case 'rejected':
        return 'Rejected';
      case 'canceled':
      case 'cancelled':
        return 'Canceled';
      default:
        return status?.toString() ?? 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: driver?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Text("Job history could not load: ${snapshot.error}");
        }

        if (!snapshot.hasData) return const SizedBox();

        final docs = snapshot.data!.docs;

        final current = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final status = data['status']?.toString().toLowerCase();
          return status == 'accepted' || status == 'intransit';
        }).toList();

        final completed = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['status']?.toString().toLowerCase() == 'completed';
        }).toList();

        final other = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final status = data['status']?.toString().toLowerCase();
          return status != 'accepted' &&
              status != 'intransit' &&
              status != 'completed';
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
                    subtitle: Text("Status: ${formatStatus(data['status'])}"),
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
            if (other.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                "Other Assigned Jobs",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ...other.map((job) {
                final data = job.data() as Map<String, dynamic>;
                return Card(
                  child: ListTile(
                    title: Text("${data['pickup']} -> ${data['dropoff']}"),
                    subtitle: Text("Status: ${formatStatus(data['status'])}"),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }
}
