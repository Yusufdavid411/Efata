import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverActiveJobsScreen extends StatelessWidget {
  const DriverActiveJobsScreen({super.key});

  Future<void> startTransit(String id) async {
    await FirebaseFirestore.instance
        .collection('orders')
        .doc(id)
        .update({
      'status': 'inTransit',
      'startedAt': Timestamp.now(),
    });
  }

  Future<void> completeJob(String id) async {
    await FirebaseFirestore.instance
        .collection('orders')
        .doc(id)
        .update({
      'status': 'completed',
      'completedAt': Timestamp.now(),
    });
  }

  String formatTime(Timestamp? ts) {
    if (ts == null) return 'Not available';
    final d = ts.toDate();
    return "${d.day}/${d.month} ${d.hour}:${d.minute}";
  }

  @override
  Widget build(BuildContext context) {
    final driver = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Current Job"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('driverId', isEqualTo: driver?.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          // 🔥 FIND ONLY ACTIVE JOB
          final active = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'];
            return status == 'accepted' || status == 'inTransit';
          }).toList();

          if (active.isEmpty) {
            return const Center(child: Text("No active job"));
          }

          final job = active.first;
          final data = job.data() as Map<String, dynamic>;

          final pickup = data['pickup'] ?? 'No pickup';
          final dropoff = data['dropoff'] ?? 'No drop-off';
          final item = data['item'] ?? 'No item';
          final status = data['status'] ?? 'unknown';
          final createdAt = data['createdAt'];

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$pickup → $dropoff",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text("Item: $item"),
                    const SizedBox(height: 6),
                    Text("Status: $status"),
                    const SizedBox(height: 6),
                    Text("Created: ${formatTime(createdAt)}"),

                    const SizedBox(height: 20),

                    if (status == 'accepted')
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => startTransit(job.id),
                          child: const Text("Start Transit"),
                        ),
                      ),

                    if (status == 'inTransit')
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => completeJob(job.id),
                          child: const Text("Mark Completed"),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}