import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverHistorySection extends StatelessWidget {
  const DriverHistorySection({super.key});

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
          return const CircularProgressIndicator();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Text("No job history yet");
        }

        final history = snapshot.data!.docs;

        return Column(
          children: history.map((job) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title:
                    Text("${job['pickup']} → ${job['dropoff']}"),
                subtitle: Text(job['status']),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}