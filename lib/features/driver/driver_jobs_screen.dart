import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'driver_active_jobs_screen.dart';

class DriverJobsScreen extends StatelessWidget {
  const DriverJobsScreen({super.key});

  String formatDateTime(dynamic timestamp) {
    if (timestamp == null || timestamp is! Timestamp) return 'Not available';

    final date = timestamp.toDate();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '${date.day}/${date.month}/${date.year} at $hour:$minute';
  }

  String formatPrice(dynamic price) {
    if (price == null) return 'No price';

    if (price is num) {
      return 'NGN ${price.toStringAsFixed(0)}';
    }

    final parsed = double.tryParse(price.toString());
    if (parsed != null) {
      return 'NGN ${parsed.toStringAsFixed(0)}';
    }

    return 'No price';
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

  int sortTime(QueryDocumentSnapshot job) {
    final data = job.data() as Map<String, dynamic>;
    final timestamps = [
      data['completedAt'],
      data['startedAt'],
      data['acceptedAt'],
      data['createdAt'],
    ];

    for (final value in timestamps) {
      if (value is Timestamp) {
        return value.millisecondsSinceEpoch;
      }
    }

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job History')),
        body: const Center(child: Text('Driver not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Job History'), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('driverId', isEqualTo: driver.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Something went wrong: ${snapshot.error}'),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          final currentJobs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status']?.toString().toLowerCase();
            return status == 'accepted' || status == 'intransit';
          }).toList();

          final completedJobs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['status']?.toString().toLowerCase() == 'completed';
          }).toList();

          final otherJobs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status']?.toString().toLowerCase();
            return status != 'accepted' &&
                status != 'intransit' &&
                status != 'completed';
          }).toList();

          completedJobs.sort((a, b) => sortTime(b).compareTo(sortTime(a)));
          otherJobs.sort((a, b) => sortTime(b).compareTo(sortTime(a)));

          if (currentJobs.isEmpty &&
              completedJobs.isEmpty &&
              otherJobs.isEmpty) {
            return const Center(child: Text('No assigned jobs yet'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Current Job',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              if (currentJobs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No current job'),
                  ),
                )
              else
                ...currentJobs.map((job) {
                  final data = job.data() as Map<String, dynamic>;

                  return Card(
                    color: Colors.blue.shade50,
                    child: ListTile(
                      title: Text(
                        '${data['pickup'] ?? 'Pickup'} -> ${data['dropoff'] ?? 'Drop-off'}',
                      ),
                      subtitle: Text('Status: ${formatStatus(data['status'])}'),
                      trailing: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DriverActiveJobsScreen(),
                            ),
                          );
                        },
                        child: const Text('View'),
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 24),

              const Text(
                'Recent Jobs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              if (completedJobs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No completed jobs yet'),
                  ),
                )
              else
                ...completedJobs.map((job) {
                  final data = job.data() as Map<String, dynamic>;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(
                        '${data['pickup'] ?? 'Pickup'} -> ${data['dropoff'] ?? 'Drop-off'}',
                      ),
                      subtitle: Text(
                        'Completed: ${formatDateTime(data['completedAt'])}',
                      ),
                      trailing: Text(
                        formatPrice(data['price']),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  );
                }),
              if (otherJobs.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'Other Assigned Jobs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ...otherJobs.map((job) {
                  final data = job.data() as Map<String, dynamic>;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(
                        '${data['pickup'] ?? 'Pickup'} -> ${data['dropoff'] ?? 'Drop-off'}',
                      ),
                      subtitle: Text('Status: ${formatStatus(data['status'])}'),
                      trailing: Text(formatPrice(data['price'])),
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}
