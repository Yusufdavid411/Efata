import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
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
        throw Exception(
          data['error']?['message'] ?? 'Cloudinary upload failed',
        );
      }

      final imageUrl = data['secure_url'];
      if (imageUrl == null) {
        throw Exception('No image URL returned from Cloudinary');
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoUrl': imageUrl,
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Profile picture updated")));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
    } finally {
      if (mounted) {
        setState(() => isUploading = false);
      }
    }
  }

  Future<void> showEditProfileForm(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final nameController = TextEditingController(
      text: data['fullName']?.toString() == 'Customer profile not completed'
          ? ''
          : data['fullName']?.toString() ?? '',
    );

    final phoneController = TextEditingController(
      text: data['phone']?.toString() == 'Not added'
          ? ''
          : data['phone']?.toString() ?? '',
    );

    final addressController = TextEditingController(
      text: data['address']?.toString() == 'Not added'
          ? ''
          : data['address']?.toString() ?? '',
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Edit Profile",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 20),

                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Full Name",
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),

                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: "Phone Number",
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),

                TextField(
                  controller: addressController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: "Address",
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      final phone = phoneController.text.trim();
                      final address = addressController.text.trim();

                      if (name.isEmpty || phone.isEmpty || address.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Please complete all fields"),
                          ),
                        );
                        return;
                      }

                      try {
                        await user.updateDisplayName(name);

                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .set({
                              'customerId': user.uid,
                              'uid': user.uid,
                              'email': user.email,
                              'name': name,
                              'fullName': name,
                              'phone': phone,
                              'address': address,
                              'role': 'customer',
                              'updatedAt': Timestamp.now(),
                            }, SetOptions(merge: true));

                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Profile updated successfully"),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Update failed: $e")),
                        );
                      }
                    },
                    child: const Text("Save Changes"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Customer Profile")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.hasData && snapshot.data!.exists
              ? snapshot.data!.data() as Map<String, dynamic>
              : <String, dynamic>{};

          final fullName =
              data['fullName']?.toString() ??
              data['name']?.toString() ??
              user.displayName ??
              'Customer profile not completed';

          final phone = data['phone']?.toString() ?? 'Not added';
          final address = data['address']?.toString() ?? 'Not added';
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
                          backgroundImage: photoUrl != null
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl == null
                              ? const Icon(Icons.person, size: 52)
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
                              onPressed: isUploading
                                  ? null
                                  : uploadProfilePicture,
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
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Card(
                child: Column(
                  children: [
                    infoTile(
                      icon: Icons.phone_outlined,
                      title: "Phone",
                      value: phone,
                    ),
                    infoTile(
                      icon: Icons.email_outlined,
                      title: "Email",
                      value: user.email ?? "No email",
                    ),
                    infoTile(
                      icon: Icons.location_on_outlined,
                      title: "Address",
                      value: address,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text("Edit Profile"),
                  onPressed: () => showEditProfileForm(data),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
