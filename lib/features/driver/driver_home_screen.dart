import 'package:flutter/material.dart';
import '../../shared/widgets/app_drawer.dart';
import 'widgets/driver_status_toggle.dart';
import 'widgets/available_jobs_section.dart';
import 'widgets/driver_history_section.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool isOnline = false;

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
              onChanged: (v) {
                setState(() {
                  isOnline = v;
                });
              },
            ),

            const SizedBox(height: 20),

            const Text(
              "Available Jobs",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            AvailableJobsSection(isOnline: isOnline),

            const SizedBox(height: 30),

            const Text(
              "Job History",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            const DriverHistorySection(),
          ],
        ),
      ),
    );
  }
}