import 'package:flutter/material.dart';
import '../../shared/widgets/app_drawer.dart';
import 'widgets/driver_status_toggle.dart';
import 'widgets/available_jobs_section.dart';
import 'widgets/driver_history_section.dart';
import 'widgets/driver_earnings_summary.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool isOnline = false;

  Future<void> handleStatusChange(bool value) async {
    if (!value) {
      final shouldGoOffline = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Go Offline?"),
          content: const Text(
            "If you go offline, you will not receive the latest available jobs until you come online again.",
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

      if (shouldGoOffline == true) {
        setState(() {
          isOnline = false;
        });
      }

      return;
    }

    setState(() {
      isOnline = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(isDriver: true),
      appBar: AppBar(
        title: const Text("Driver Dashboard"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            DriverStatusToggle(
              isOnline: isOnline,
              onChanged: handleStatusChange,
            ),
            const SizedBox(height: 20),
            const DriverEarningsSummary(),
            const SizedBox(height: 24),
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
    );
  }
}