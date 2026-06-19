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
  bool isLoadingAvailability = true;
  String verificationStatus = 'incomplete';
  bool profileCompleted = false;

  @override
  void initState() {
    super.initState();
    loadDriverAvailability();
  }

  Future<void> loadDriverAvailability() async {
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) {
      if (mounted) setState(() => isLoadingAvailability = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driver.uid)
          .get();

      final data = doc.data();
      final savedStatus =
          data?['isOnline'] == true || data?['isAvailable'] == true;

      if (!mounted) return;

      setState(() {
        isOnline = savedStatus;
        verificationStatus =
            data?['verificationStatus']?.toString() ?? 'incomplete';
        profileCompleted = data?['profileCompleted'] == true;
        isLoadingAvailability = false;
      });
    } catch (_) {
      if (mounted) setState(() => isLoadingAvailability = false);
    }
  }

  Future<void> handleStatusChange(bool value) async {
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) return;

    if (value &&
        (!profileCompleted || verificationStatus.toLowerCase() != 'approved')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !profileCompleted
                ? 'Complete your driver profile before going online.'
                : 'Your account must be approved before receiving jobs.',
          ),
        ),
      );
      return;
    }

    if (!value) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Go Offline?"),
          content: const Text("You won't receive new jobs while offline."),
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

    await FirebaseFirestore.instance.collection('drivers').doc(driver.uid).set({
      'isOnline': value,
      'isAvailable': value,
      'availabilityUpdatedAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));

    setState(() => isOnline = value);
  }

  Widget verificationCard() {
    final status = verificationStatus.toLowerCase();
    final approved = status == 'approved';
    final color = approved
        ? Colors.green
        : status == 'pending'
        ? Colors.orange
        : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            approved
                ? Icons.verified_user_outlined
                : Icons.pending_actions_outlined,
            color: color.shade700,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  approved ? 'Driver approved' : 'Driver approval required',
                  style: TextStyle(
                    color: color.shade900,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  approved
                      ? 'You can go online and receive delivery requests.'
                      : 'Complete your profile and wait for admin approval before accepting jobs.',
                  style: const TextStyle(color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget currentJobCard() {
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: driver.uid)
          .limit(25)
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
        final vehicleType = data['vehicleType']?.toString();

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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text("$pickup -> $dropoff"),
                const SizedBox(height: 6),
                Text("Status: $status"),
                if (vehicleType != null && vehicleType.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text("Vehicle: $vehicleType"),
                ],
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
      appBar: AppBar(title: const Text("Driver Dashboard")),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                const DriverEarningsSummary(),
                const SizedBox(height: 20),

                verificationCard(),

                DriverStatusToggle(
                  isOnline: isOnline,
                  isLoading: isLoadingAvailability,
                  onChanged: handleStatusChange,
                ),

                const SizedBox(height: 20),

                currentJobCard(),

                const Text(
                  "Available Jobs",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 10),

                AvailableJobsSection(isOnline: isOnline),

                const SizedBox(height: 30),

                const Text(
                  "Job History",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
