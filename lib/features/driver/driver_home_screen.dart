import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/ai_floating_button.dart';
import 'widgets/driver_status_toggle.dart';
import 'widgets/available_jobs_section.dart';
import 'widgets/driver_history_section.dart';
import 'widgets/driver_earnings_summary.dart';
import 'driver_active_jobs_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool isOnline = false;

  Future<void> handleStatusChange(bool value) async {
    if (!value) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Go Offline?"),
          content: const Text(
            "You won’t receive new jobs while offline.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Go Offline"),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    setState(() => isOnline = value);
  }

  Widget currentJobCard() {
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: driver.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        final docs = snapshot.data!.docs;

        final activeJobs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'];
          return status == 'accepted' || status == 'inTransit';
        }).toList();

        if (activeJobs.isEmpty) return const SizedBox();

        final job = activeJobs.first;
        final data = job.data() as Map<String, dynamic>;

        final pickup = data['pickup']?.toString() ?? 'No pickup location';
        final dropoff = data['dropoff']?.toString() ?? 'No drop-off location';
        final status = data['status']?.toString() ?? 'accepted';

        return Card(
          color: Colors.blue.shade50,
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Current Job",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text("$pickup → $dropoff"),
                const SizedBox(height: 6),
                Text("Status: $status"),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DriverActiveJobsScreen(),
                      ),
                    );
                  },
                  child: const Text("View Job"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(isDriver: true),
      appBar: AppBar(
        title: const Text("Driver Dashboard"),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                const DriverEarningsSummary(),
                const SizedBox(height: 20),

                DriverStatusToggle(
                  isOnline: isOnline,
                  onChanged: handleStatusChange,
                ),

                const SizedBox(height: 20),

                currentJobCard(),

                const Text(
                  "Available Jobs",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                AvailableJobsSection(isOnline: isOnline),

                const SizedBox(height: 30),

                const Text(
                  "Job History",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                const DriverHistorySection(),
              ],
            ),
          ),

          const AIFloatingButton(),
        ],
      ),
    );
  }
}