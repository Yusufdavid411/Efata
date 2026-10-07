import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import '../../../core/services/app_notification_banner_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/widgets/app_bottom_navigation.dart';

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key, this.embedded = false});

  final bool embedded;

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

      AppNotificationBannerService.success(
        'Profile picture updated.',
        title: 'Profile updated',
      );
    } catch (e) {
      if (!mounted) return;

      AppNotificationBannerService.error(
        'Upload failed: $e',
        title: 'Upload failed',
      );
    } finally {
      if (mounted) {
        setState(() => isUploading = false);
      }
    }
  }

  Future<void> showEditProfileForm(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final savedName = _customerNameFromData(data);
    final nameController = TextEditingController(
      text: savedName == 'Customer' ? '' : savedName,
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
                const SizedBox(height: 6),
                const Text(
                  'Update your display name. Phone, email, and address can be edited directly from your profile details.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), height: 1.35),
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

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = nameController.text.trim();

                      if (name.isEmpty) {
                        AppNotificationBannerService.error(
                          'Please enter your full name.',
                          title: 'Missing details',
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
                              'role': 'customer',
                              'profileCompleted': true,
                              'onboardingSkipped': false,
                              'updatedAt': Timestamp.now(),
                            }, SetOptions(merge: true));

                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }

                        if (!mounted) return;
                        AppNotificationBannerService.success(
                          'Profile updated successfully.',
                          title: 'Profile updated',
                        );
                      } catch (e) {
                        if (!mounted) return;
                        AppNotificationBannerService.error(
                          'Update failed: $e',
                          title: 'Update failed',
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

  Future<void> showEditDetailSheet({
    required String field,
    required String title,
    required String currentValue,
    required TextInputType keyboardType,
    int maxLines = 1,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final controller = TextEditingController(
      text: currentValue == 'Not added' ? '' : currentValue,
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit $title',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: keyboardType,
                maxLines: maxLines,
                decoration: InputDecoration(
                  labelText: title,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final value = controller.text.trim();
                    if (value.isEmpty) {
                      AppNotificationBannerService.error(
                        '$title cannot be empty.',
                        title: 'Missing detail',
                      );
                      return;
                    }

                    try {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .set({
                            field: value,
                            'profileCompleted': true,
                            'updatedAt': Timestamp.now(),
                          }, SetOptions(merge: true));

                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (!mounted) return;
                      AppNotificationBannerService.success(
                        '$title updated successfully.',
                        title: 'Profile updated',
                      );
                    } catch (e) {
                      if (!mounted) return;
                      AppNotificationBannerService.error(
                        'Update failed: $e',
                        title: 'Update failed',
                      );
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> showEditEmailSheet(String currentEmail) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final controller = TextEditingController(text: currentEmail);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit Email',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'EFATA will send a verification link to the new email before it becomes active.',
                style: TextStyle(color: Color(0xFF64748B), height: 1.35),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final email = controller.text.trim();
                    if (email.isEmpty || !email.contains('@')) {
                      AppNotificationBannerService.error(
                        'Enter a valid email address.',
                        title: 'Invalid email',
                      );
                      return;
                    }

                    if (email.toLowerCase() == currentEmail.toLowerCase()) {
                      Navigator.pop(sheetContext);
                      return;
                    }

                    try {
                      await user.verifyBeforeUpdateEmail(email);
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .set({
                            'pendingEmail': email,
                            'updatedAt': Timestamp.now(),
                          }, SetOptions(merge: true));

                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (!mounted) return;
                      AppNotificationBannerService.success(
                        'Check $email to confirm your new email address.',
                        title: 'Verification sent',
                      );
                    } on FirebaseAuthException catch (e) {
                      if (!mounted) return;
                      final message = e.code == 'requires-recent-login'
                          ? 'Please log out and sign in again before changing your email.'
                          : e.message ?? 'Email update failed.';
                      AppNotificationBannerService.error(
                        message,
                        title: 'Email not updated',
                      );
                    } catch (e) {
                      if (!mounted) return;
                      AppNotificationBannerService.error(
                        'Email update failed: $e',
                        title: 'Email not updated',
                      );
                    }
                  },
                  child: const Text('Send Verification Link'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget infoTile({
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onEdit,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
      trailing: onEdit == null
          ? null
          : IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
              tooltip: 'Edit $title',
            ),
    );
  }

  String _customerNameFromData(Map<String, dynamic> data) {
    final fullName = data['fullName']?.toString().trim();
    if (fullName != null && fullName.isNotEmpty) return fullName;

    final name = data['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;

    return 'Customer';
  }

  Future<void> confirmLogout() async {
    final shouldLogout = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Log out of EFATA?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'You will need to sign in again before booking or tracking deliveries.',
              style: TextStyle(color: Color(0xFF64748B), height: 1.35),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(sheetContext, true),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Logout'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.pop(sheetContext, false),
              child: const Text('Stay Logged In'),
            ),
          ],
        ),
      ),
    );

    if (shouldLogout != true) return;
    await AuthService().logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    final content = StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData && snapshot.data!.exists
            ? snapshot.data!.data() as Map<String, dynamic>
            : <String, dynamic>{};

        final fullName = _customerNameFromData(data);

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
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Passenger',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w900,
                  ),
                ),
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
                    onEdit: () => showEditDetailSheet(
                      field: 'phone',
                      title: 'Phone',
                      currentValue: phone,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  infoTile(
                    icon: Icons.email_outlined,
                    title: "Email",
                    value: user.email ?? "No email",
                    onEdit: () => showEditEmailSheet(user.email ?? ''),
                  ),
                  infoTile(
                    icon: Icons.location_on_outlined,
                    title: "Address",
                    value: address,
                    onEdit: () => showEditDetailSheet(
                      field: 'address',
                      title: 'Address',
                      currentValue: address,
                      keyboardType: TextInputType.streetAddress,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _ProfileActionCard(
              children: [
                _ProfileActionTile(
                  icon: Icons.edit_outlined,
                  title: 'Edit Profile',
                  subtitle: 'Update your display name',
                  onTap: () => showEditProfileForm(data),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ProfileActionCard(
              children: [
                _ProfileActionTile(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  subtitle: 'Theme, notifications, and sign-in',
                  onTap: () => Navigator.pushNamed(context, '/settings'),
                ),
                _ProfileActionTile(
                  icon: Icons.support_agent_outlined,
                  title: 'Help & Support',
                  subtitle: 'Get help with booking and tracking',
                  onTap: () => Navigator.pushNamed(context, '/settings'),
                ),
                _ProfileActionTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Trust & Safety',
                  subtitle: 'Account protection and delivery support',
                  onTap: () => Navigator.pushNamed(context, '/settings'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _LogoutTile(onTap: confirmLogout),
            const SizedBox(height: 20),
          ],
        );
      },
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Customer Profile"),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const AppBottomNavigation(
        isDriver: false,
        currentIndex: 3,
      ),
      body: content,
    );
  }
}

class _ProfileActionCard extends StatelessWidget {
  const _ProfileActionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(child: Column(children: children));
  }
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF0F766E)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF1F2),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Logout',
                      style: TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Leave this device signed out',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Color(0xFFDC2626)),
            ],
          ),
        ),
      ),
    );
  }
}
