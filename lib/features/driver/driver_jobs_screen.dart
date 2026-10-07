import 'package:flutter/material.dart';

import '../../shared/widgets/app_bottom_navigation.dart';
import 'widgets/driver_current_job_card.dart';
import 'widgets/driver_history_section.dart';

class DriverJobsScreen extends StatelessWidget {
  const DriverJobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job History'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const AppBottomNavigation(
        isDriver: true,
        currentIndex: 1,
      ),
      body: const DriverJobsContent(),
    );
  }
}

class DriverJobsContent extends StatelessWidget {
  const DriverJobsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DriverCurrentJobCard(showEmptyState: true),
            DriverHistorySection(),
          ],
        ),
      ),
    );
  }
}
