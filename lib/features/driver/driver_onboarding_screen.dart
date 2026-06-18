import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
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
  bool isUploadingLicense = false;
  bool isSaving = false;
  String? licenseUrl;

  Future<void> uploadLicense() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => isUploadingLicense = true);

    try {
      final file = File(image.path);
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/dk21bi5fg/image/upload',
      );

      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = 'profile_upload'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(data['error']?['message'] ?? 'License upload failed');
      }

      final uploadedUrl = data['secure_url']?.toString();
      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        throw Exception('No license URL returned');
      }

      if (!mounted) return;
      setState(() {
        licenseUrl = uploadedUrl;
        licenseUploaded = true;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Driver license uploaded')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) {
        setState(() => isUploadingLicense = false);
      }
    }
  }

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
      'licenseUrl': licenseUrl,
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
        'licenseUrl': null,
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
              icon: isUploadingLicense
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(
                isUploadingLicense
                    ? 'Uploading license...'
                    : licenseUploaded
                    ? 'Driver License Uploaded'
                    : 'Upload Driver License',
              ),
              onPressed: isUploadingLicense ? null : uploadLicense,
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
