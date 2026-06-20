import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/ai_floating_button.dart';
import 'widgets/driver_status_toggle.dart';
import 'widgets/available_jobs_section.dart';
import 'widgets/driver_current_job_card.dart';
import 'widgets/driver_history_section.dart';
import 'widgets/driver_earnings_summary.dart';

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

    if (approved) return const SizedBox.shrink();

    final color = approved
        ? Colors.green
        : status == 'pending'
        ? Colors.orange
        : Colors.red;
    final title = !profileCompleted
        ? 'Complete driver profile'
        : status == 'pending'
        ? 'Approval in review'
        : 'Driver approval required';
    final message = !profileCompleted
        ? 'Add your vehicle and contact details so admin can verify your account.'
        : status == 'pending'
        ? 'Admin is reviewing your driver profile. You can go online after approval.'
        : 'Your account must be approved before you can receive delivery requests.';

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
                  title,
                  style: TextStyle(
                    color: color.shade900,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: Color(0xFF475569))),
              ],
            ),
          ),
        ],
      ),
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

                const DriverCurrentJobCard(),

                const Text(
                  "Available Jobs",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 10),

                AvailableJobsSection(isOnline: isOnline),

                const SizedBox(height: 30),

                const DriverHistorySection(maxItems: 5),
              ],
            ),
          ),

          const AIFloatingButton(),
        ],
      ),
    );
  }
}
