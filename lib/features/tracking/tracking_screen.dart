import 'package:flutter/material.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tracking')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: const [
            Text('Tracking details will appear here'),
            SizedBox(height: 12),
            Expanded(child: Center(child: Text('Map / route placeholder'))),
          ],
        ),
      ),
    );
  }
}
