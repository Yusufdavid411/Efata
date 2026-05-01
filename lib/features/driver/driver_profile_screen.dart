import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  bool isUploading = false;

  Future<void> uploadProfilePicture() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => isUploading = true);

    try {
      final file = File(image.path);
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/dk21bi5fg/image/upload',
      );

      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = 'profile_upload'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send();
      final resBody = await response.stream.bytesToString();
      final data = jsonDecode(resBody);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(data['error']?['message'] ?? 'Cloudinary upload failed');
      }

      final imageUrl = data['secure_url'];
      if (imageUrl == null) {
        throw Exception('No image URL returned from Cloudinary');
      }

      await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set({
        'photoUrl': imageUrl,
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile picture updated")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Upload failed: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => isUploading = false);
      }
    }
  }

  Future<void> updateField({
    required String field,
    required String title,
    required String currentValue,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final controller = TextEditingController(
      text: currentValue == 'Not added' ||
              currentValue == 'Driver profile not completed'
          ? ''
          : currentValue,
    );

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();

              if (value.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Field cannot be empty")),
                );
                return;
              }

              try {
                await FirebaseFirestore.instance
                    .collection('drivers')
                    .doc(user.uid)
                    .set({
                  field: value,
                  'updatedAt': Timestamp.now(),
                }, SetOptions(merge: true));

                if (field == 'fullName') {
                  await user.updateDisplayName(value);
                }

                if (dialogContext.mounted) Navigator.pop(dialogContext);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("$title updated successfully")),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Update failed: $e")),
                  );
                }
              }
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

    String selected = currentValue == 'Not added' ? 'Car' : currentValue;

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Update Vehicle"),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return DropdownButtonFormField<String>(
              value: selected,
              decoration: const InputDecoration(
                labelText: "Vehicle Type",
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
                if (value != null) {
                  setDialogState(() => selected = value);
                }
              },
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('drivers')
                    .doc(user.uid)
                    .set({
                  'vehicleType': selected,
                  'updatedAt': Timestamp.now(),
                }, SetOptions(merge: true));

                if (dialogContext.mounted) Navigator.pop(dialogContext);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Vehicle updated successfully")),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Update failed: $e")),
                  );
                }
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Widget tile({
    required String title,
    required String value,
    required IconData icon,
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
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
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

          final name =
              data['fullName']?.toString() ?? 'Driver profile not completed';
          final phone = data['phone']?.toString() ?? 'Not added';
          final vehicle = data['vehicleType']?.toString() ?? 'Not added';
          final plate = data['plateNumber']?.toString() ?? 'Not added';
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
                          radius: 50,
                          backgroundImage:
                              photoUrl != null ? NetworkImage(photoUrl) : null,
                          child: photoUrl == null
                              ? const Icon(Icons.person, size: 50)
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            backgroundColor: Colors.deepPurple,
                            child: IconButton(
                              icon: isUploading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
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
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Card(
                child: Column(
                  children: [
                    tile(
                      title: "Full Name",
                      value: name,
                      icon: Icons.person,
                      onEdit: () => updateField(
                        field: 'fullName',
                        title: 'Full Name',
                        currentValue: name,
                      ),
                    ),
                    tile(
                      title: "Phone",
                      value: phone,
                      icon: Icons.phone,
                      onEdit: () => updateField(
                        field: 'phone',
                        title: 'Phone',
                        currentValue: phone,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text("Email"),
                      subtitle: Text(user.email ?? 'No email'),
                    ),
                    tile(
                      title: "Vehicle",
                      value: vehicle,
                      icon: Icons.local_shipping,
                      onEdit: () => updateVehicleType(vehicle),
                    ),
                    tile(
                      title: "Plate Number",
                      value: plate,
                      icon: Icons.confirmation_number,
                      onEdit: () => updateField(
                        field: 'plateNumber',
                        title: 'Plate Number',
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