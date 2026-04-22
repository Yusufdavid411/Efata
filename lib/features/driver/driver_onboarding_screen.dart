import 'package:flutter/material.dart';
import 'driver_home_screen.dart';

class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  State<DriverOnboardingScreen> createState() =>
      _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController plateController = TextEditingController();

  String vehicleType = 'Car';
  bool licenseUploaded = false;

  void submit() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Onboarding'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: vehicleType,
              decoration: const InputDecoration(
                labelText: 'Vehicle Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Car', child: Text('Car')),
                DropdownMenuItem(value: 'Van', child: Text('Van')),
                DropdownMenuItem(value: 'Truck', child: Text('Truck')),
              ],
              onChanged: (v) => setState(() => vehicleType = v!),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: plateController,
              decoration: const InputDecoration(
                labelText: 'Vehicle Plate Number',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(
                licenseUploaded
                    ? 'Driver License Uploaded'
                    : 'Upload Driver License',
              ),
              onPressed: () {
                setState(() => licenseUploaded = true);
              },
            ),

            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: submit,
              child: const Text('Continue to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
