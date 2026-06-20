import 'package:flutter/material.dart';

import 'widgets/driver_history_section.dart';

class DriverJobsScreen extends StatelessWidget {
  const DriverJobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Job History'), centerTitle: true),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: DriverHistorySection(),
        ),
      ),
    );
  }
}
