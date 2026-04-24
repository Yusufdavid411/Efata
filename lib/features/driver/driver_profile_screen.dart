import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'driver_onboarding_screen.dart';

class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  Color getStatusColor(String status) {
    switch (status) {
      case 'verified':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String formatStatus(String status) {
    switch (status) {
      case 'verified':
        return 'Verified';
      case 'rejected':
        return 'Rejected';
      case 'pending':
        return 'Pending Verification';
      default:
        return 'Incomplete Profile';
    }
  }

  Widget infoTile(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            "$title: ",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Profile")),
        body: const Center(child: Text("Not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final exists = snapshot.hasData && snapshot.data!.exists;
          final data = exists
              ? snapshot.data!.data() as Map<String, dynamic>
              : null;

          final fullName = data?['fullName'] ?? user.displayName ?? "No name";
          final email = user.email ?? "";
          final phone = data?['phone'] ?? "Not added";
          final vehicle = data?['vehicleType'] ?? "Not set";
          final plate = data?['plateNumber'] ?? "Not set";
          final status = data?['verificationStatus'] ?? "incomplete";
          final licenseUploaded = data?['licenseUploaded'] == true;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 👤 HEADER
              Column(
                children: [
                  const CircleAvatar(
                    radius: 40,
                    child: Icon(Icons.person, size: 40),
                  ),
                  const SizedBox(height: 10),

                  Text(
                    fullName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  Text(
                    email,
                    style: const TextStyle(color: Colors.grey),
                  ),

                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      formatStatus(status),
                      style: TextStyle(
                        color: getStatusColor(status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 25),

              // 📋 DETAILS
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      infoTile("Phone", phone),
                      infoTile("Vehicle", vehicle),
                      infoTile("Plate", plate),
                      infoTile(
                        "License",
                        licenseUploaded ? "Uploaded" : "Not uploaded",
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 🔥 COMPLETE PROFILE BUTTON
              if (!exists || status == 'incomplete')
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DriverOnboardingScreen(),
                      ),
                    );
                  },
                  child: const Text("Complete Profile"),
                ),

              const SizedBox(height: 10),

              // ✏️ EDIT (future)
              OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Edit coming soon")),
                  );
                },
                child: const Text("Edit Profile"),
              ),

              const SizedBox(height: 10),

              // 🌙 DARK MODE UI
              SwitchListTile(
                value: false,
                onChanged: (_) {},
                title: const Text("Dark Mode"),
              ),
            ],
          );
        },
      ),
    );
  }
}