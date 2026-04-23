import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool isSaving = false;

  Future<void> submit() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Driver not logged in")),
      );
      return;
    }

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

    setState(() {
      isSaving = true;
    });

    await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set({
      'driverId': user.uid,
      'email': user.email,
      'fullName': nameController.text.trim(),
      'phone': phoneController.text.trim(),
      'vehicleType': vehicleType,
      'plateNumber': plateController.text.trim(),
      'licenseUploaded': licenseUploaded,
      'verificationStatus': 'pending',
      'isOnline': false,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    setState(() {
      isSaving = false;
    });

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
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              "Your details will be reviewed before full verification.",
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
              value: vehicleType,
              decoration: const InputDecoration(
                labelText: 'Vehicle Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Car', child: Text('Car')),
                DropdownMenuItem(value: 'Van', child: Text('Van')),
                DropdownMenuItem(value: 'Truck', child: Text('Truck')),
                DropdownMenuItem(value: 'Bike', child: Text('Bike')),
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
              child: Text(
                isSaving ? 'Saving...' : 'Continue to Dashboard',
              ),
            ),
          ],
        ),
      ),
    );
  }
}