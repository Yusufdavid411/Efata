import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  bool isUploading = false;

  Color statusColor(String status) {
    switch (status) {
      case 'verified':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String statusText(String status) {
    switch (status) {
      case 'verified':
        return 'Verified';
      case 'pending':
        return 'Pending Verification';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Incomplete Profile';
    }
  }

  Future<void> uploadProfilePicture() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => isUploading = true);

    final file = File(image.path);

    final ref = FirebaseStorage.instance
        .ref()
        .child('driver_profile_pictures')
        .child('${user.uid}.jpg');

    await ref.putFile(file);

    final imageUrl = await ref.getDownloadURL();

    await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set({
      'photoUrl': imageUrl,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));

    if (mounted) {
      setState(() => isUploading = false);
    }
  }

  Future<void> updateField({
    required String title,
    required String field,
    required String currentValue,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final controller = TextEditingController(
      text: currentValue == 'Not added' || currentValue == 'Not set'
          ? ''
          : currentValue,
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Update $title"),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: title,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();

              if (value.isEmpty) return;

              await FirebaseFirestore.instance
                  .collection('drivers')
                  .doc(user.uid)
                  .set({
                field: value,
                if (field == 'fullName') 'profileCompleted': true,
                'updatedAt': Timestamp.now(),
              }, SetOptions(merge: true));

              if (field == 'fullName') {
                await user.updateDisplayName(value);
              }

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> updateVehicleType(String currentValue) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String selected = currentValue == 'Not added' || currentValue == 'Not set'
        ? 'Car'
        : currentValue;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Update Vehicle Type"),
        content: DropdownButtonFormField<String>(
          value: selected,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Car', child: Text('Car')),
            DropdownMenuItem(value: 'Van', child: Text('Van')),
            DropdownMenuItem(value: 'Truck', child: Text('Truck')),
            DropdownMenuItem(value: 'Bike', child: Text('Bike')),
            DropdownMenuItem(value: 'Pickup', child: Text('Pickup')),
          ],
          onChanged: (value) {
            if (value != null) selected = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('drivers')
                  .doc(user.uid)
                  .set({
                'vehicleType': selected,
                'updatedAt': Timestamp.now(),
              }, SetOptions(merge: true));

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Widget editableTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onEdit,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        onPressed: onEdit,
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
          final data = snapshot.hasData && snapshot.data!.exists
              ? snapshot.data!.data() as Map<String, dynamic>
              : <String, dynamic>{};

          final fullName = data['fullName']?.toString() ??
              user.displayName ??
              'Driver profile not completed';
          final phone = data['phone']?.toString() ?? 'Not added';
          final email = user.email ?? 'No email';
          final vehicle = data['vehicleType']?.toString() ?? 'Not set';
          final plate = data['plateNumber']?.toString() ?? 'Not set';
          final status = data['verificationStatus']?.toString() ?? 'incomplete';
          final photoUrl = data['photoUrl']?.toString();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundImage:
                              photoUrl != null ? NetworkImage(photoUrl) : null,
                          child: photoUrl == null
                              ? const Icon(Icons.person, size: 52)
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.deepPurple,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: isUploading
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                              onPressed:
                                  isUploading ? null : uploadProfilePicture,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      fullName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor(status).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusText(status),
                        style: TextStyle(
                          color: statusColor(status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Card(
                child: Column(
                  children: [
                    editableTile(
                      icon: Icons.person_outline,
                      title: "Full Name",
                      value: fullName,
                      onEdit: () => updateField(
                        title: "Full Name",
                        field: "fullName",
                        currentValue: fullName,
                      ),
                    ),
                    editableTile(
                      icon: Icons.phone_outlined,
                      title: "Phone Number",
                      value: phone,
                      onEdit: () => updateField(
                        title: "Phone Number",
                        field: "phone",
                        currentValue: phone,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text("Email"),
                      subtitle: Text(email),
                    ),
                    editableTile(
                      icon: Icons.local_shipping_outlined,
                      title: "Vehicle Type",
                      value: vehicle,
                      onEdit: () => updateVehicleType(vehicle),
                    ),
                    editableTile(
                      icon: Icons.confirmation_number_outlined,
                      title: "Plate Number",
                      value: plate,
                      onEdit: () => updateField(
                        title: "Plate Number",
                        field: "plateNumber",
                        currentValue: plate,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}