import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/services/app_notification_banner_service.dart';

class CustomerOnboardingScreen extends StatefulWidget {
  const CustomerOnboardingScreen({super.key});

  @override
  State<CustomerOnboardingScreen> createState() =>
      _CustomerOnboardingScreenState();
}

class _CustomerOnboardingScreenState extends State<CustomerOnboardingScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    nameController.text = user?.displayName ?? '';
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final address = addressController.text.trim();

    if (name.isEmpty || phone.isEmpty || address.isEmpty) {
      AppNotificationBannerService.error(
        'Add your name, phone number, and main pickup address.',
        title: 'Complete profile',
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      await user.updateDisplayName(name);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'customerId': user.uid,
        'email': user.email,
        'name': name,
        'fullName': name,
        'phone': phone,
        'address': address,
        'role': 'customer',
        'profileCompleted': true,
        'onboardingSkipped': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      AppNotificationBannerService.success(
        'Your customer profile is ready.',
        title: 'Profile completed',
      );
      Navigator.pushNamedAndRemoveUntil(context, '/customerHome', (_) => false);
    } catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        'Profile setup failed: $e',
        title: 'Setup failed',
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> skip() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'customerId': user.uid,
        'email': user.email,
        'name': user.displayName ?? user.email?.split('@').first ?? 'Customer',
        'fullName':
            user.displayName ?? user.email?.split('@').first ?? 'Customer',
        'role': 'customer',
        'profileCompleted': false,
        'onboardingSkipped': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/customerHome', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Setup'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(Icons.inventory_2_outlined, color: primary, size: 32),
            ),
            const SizedBox(height: 22),
            const Text(
              'Set up your customer profile',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 28,
                height: 1.08,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'These details help drivers contact you and identify your regular pickup point.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: addressController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Main pickup address',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isSaving ? null : submit,
              child: Text(isSaving ? 'Saving profile...' : 'Continue'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: isSaving ? null : skip,
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}
