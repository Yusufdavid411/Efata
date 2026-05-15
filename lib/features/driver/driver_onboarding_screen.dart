import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'driver_home_screen.dart';

class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController plateController = TextEditingController();

  String vehicleType = 'Truck';
  bool licenseUploaded = false;
  bool isSaving = false;

  Future<void> submit() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    if (nameController.text.trim().isEmpty ||
        phoneController.text.trim().isEmpty ||
        plateController.text.trim().isEmpty ||
        !licenseUploaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please complete all fields and upload your license"),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    await user.updateDisplayName(nameController.text.trim());

    await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set({
      'driverId': user.uid,
      'email': user.email,
      'fullName': nameController.text.trim(),
      'phone': phoneController.text.trim(),
      'vehicleType': vehicleType,
      'plateNumber': plateController.text.trim(),
      'licenseUploaded': licenseUploaded,
      'verificationStatus': 'pending',
      'profileCompleted': true,
      'onboardingSkipped': false,
      'isOnline': false,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    setState(() => isSaving = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
    );
  }

  Future<void> skipOnboarding() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set({
        'driverId': user.uid,
        'email': user.email,
        'fullName': user.displayName ?? 'Driver profile not completed',
        'phone': 'Not added',
        'vehicleType': 'Not added',
        'plateNumber': 'Not added',
        'licenseUploaded': false,
        'verificationStatus': 'incomplete',
        'profileCompleted': false,
        'onboardingSkipped': true,
        'isOnline': false,
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    plateController.dispose();
    super.dispose();
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
            const Text(
              "Complete your driver profile",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "You can skip now and update these details later from your profile.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
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
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: vehicleType,
              decoration: const InputDecoration(
                labelText: 'Vehicle Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Truck', child: Text('Truck')),
                DropdownMenuItem(value: 'Tipper', child: Text('Tipper')),
                DropdownMenuItem(
                  value: 'Petrol Tanker',
                  child: Text('Petrol Tanker'),
                ),
                DropdownMenuItem(value: 'Van', child: Text('Van')),
                DropdownMenuItem(value: 'Pickup', child: Text('Pickup')),
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
              onPressed: isSaving ? null : submit,
              child: Text(isSaving ? 'Saving...' : 'Continue to Dashboard'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: isSaving ? null : skipOnboarding,
              child: const Text("Skip for now"),
            ),
          ],
        ),
      ),
    );
  }
}
