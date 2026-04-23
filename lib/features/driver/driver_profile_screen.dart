import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  Color getVerificationColor(String status) {
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
        return 'Not submitted';
    }
  }

  Widget infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 115,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
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
        appBar: AppBar(title: const Text("Driver Profile")),
        body: const Center(child: Text("Driver not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Driver Profile")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text("Driver profile not completed yet"),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final fullName = data['fullName']?.toString() ?? 'Not provided';
          final phone = data['phone']?.toString() ?? 'Not provided';
          final email = data['email']?.toString() ?? user.email ?? '';
          final vehicleType =
              data['vehicleType']?.toString() ?? 'Not provided';
          final plateNumber =
              data['plateNumber']?.toString() ?? 'Not provided';
          final verificationStatus =
              data['verificationStatus']?.toString() ?? 'pending';
          final licenseUploaded = data['licenseUploaded'] == true;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 45,
                  child: Icon(Icons.person, size: 45),
                ),

                const SizedBox(height: 16),

                Text(
                  fullName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: getVerificationColor(verificationStatus)
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    formatStatus(verificationStatus),
                    style: TextStyle(
                      color: getVerificationColor(verificationStatus),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        infoRow("Email", email),
                        infoRow("Phone", phone),
                        infoRow("Vehicle", vehicleType),
                        infoRow("Plate No.", plateNumber),
                        infoRow(
                          "License",
                          licenseUploaded ? "Uploaded" : "Not uploaded",
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}