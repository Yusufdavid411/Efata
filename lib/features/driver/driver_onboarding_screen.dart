import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logistics_app/core/services/efata_api_client.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:logistics_app/core/services/app_notification_banner_service.dart';

import 'driver_home_screen.dart';

class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key, this.returnToProfile = false});

  final bool returnToProfile;

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
  String? vehiclePhotoUrl;
  bool approved = false;

  @override
  void initState() {
    super.initState();
    loadSavedProfile();
  }

  Future<void> loadSavedProfile() async {
    try {
      final account = await EfataApiClient.instance.getMe();
      if (!mounted) return;
      nameController.text = account.displayName;
      phoneController.text = account.phone ?? '';
      plateController.text =
          account.driverProfile?['plateNumber']?.toString() ?? '';
      setState(() {
        vehicleType =
            account.driverProfile?['vehicleType']?.toString() ?? 'Truck';
        approved = account.driverProfile?['verificationStatus'] == 'approved';
        vehiclePhotoUrl = account.driverProfile?['vehiclePhotoUrl']?.toString();
        licenseUrl = account.driverProfile?['licenseUrl']?.toString();
        licenseUploaded = licenseUrl?.isNotEmpty == true;
      });
    } catch (_) {
      if (mounted)
        AppNotificationBannerService.error('Could not load your profile.');
    }
  }

  Future<void> uploadLicense({bool vehicle = false}) async {
    setState(() => isUploadingLicense = true);

    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
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
        if (vehicle) {
          vehiclePhotoUrl = uploadedUrl;
        } else {
          licenseUrl = uploadedUrl;
          licenseUploaded = true;
        }
      });

      AppNotificationBannerService.success(
        vehicle ? 'Vehicle photo uploaded.' : 'Driver license uploaded.',
        title: 'Upload complete',
      );
    } catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        'Upload failed: $e',
        title: 'Upload failed',
      );
    } finally {
      if (mounted) {
        setState(() => isUploadingLicense = false);
      }
    }
  }

  Future<void> submit() async {
    if (nameController.text.trim().isEmpty ||
        phoneController.text.trim().isEmpty ||
        plateController.text.trim().isEmpty ||
        (!approved && (!licenseUploaded || vehiclePhotoUrl == null))) {
      AppNotificationBannerService.error(
        'Complete all fields and upload your license and vehicle photo.',
        title: 'Missing driver details',
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final account = await EfataApiClient.instance.updateProfile({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
        'vehicleType': vehicleType,
        'plateNumber': plateController.text.trim(),
        if (!approved && licenseUrl != null) 'licenseUrl': licenseUrl!,
        if (vehiclePhotoUrl != null) 'vehiclePhotoUrl': vehiclePhotoUrl!,
      });
      if (!mounted) return;
      if (account.driverProfile?['verificationStatus'] == 'pending') {
        AppNotificationBannerService.success(
          'Please allow 24 to 48 hours for review.',
          title: 'Documents received',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => isSaving = false);
      AppNotificationBannerService.error('Could not save your driver profile.');
      return;
    }

    if (!mounted) return;

    setState(() => isSaving = false);
    if (widget.returnToProfile) {
      Navigator.pop(context);
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
    );
  }

  Future<void> skipOnboarding() async {
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
        title: const Text('Driver Setup'),
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
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.local_shipping_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              "Set up your driver profile",
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 28,
                height: 1.08,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Add your vehicle details and license so admin can review and approve your account.",
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
                    DropdownButtonFormField<String>(
                      initialValue: vehicleType,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle type',
                        prefixIcon: Icon(Icons.local_shipping_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Truck', child: Text('Truck')),
                        DropdownMenuItem(
                          value: 'Tipper',
                          child: Text('Tipper'),
                        ),
                        DropdownMenuItem(
                          value: 'Petrol Tanker',
                          child: Text('Petrol Tanker'),
                        ),
                        DropdownMenuItem(value: 'Van', child: Text('Van')),
                        DropdownMenuItem(
                          value: 'Pickup',
                          child: Text('Pickup'),
                        ),
                        DropdownMenuItem(value: 'Mixer', child: Text('Mixer')),
                      ],
                      onChanged: (v) => setState(() => vehicleType = v!),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: plateController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle plate number',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (!approved)
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: isUploadingLicense || approved
                      ? null
                      : () => uploadLicense(),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: licenseUploaded
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: isUploadingLicense
                              ? const Padding(
                                  padding: EdgeInsets.all(13),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : Icon(
                                  licenseUploaded
                                      ? Icons.check_circle_rounded
                                      : Icons.upload_file_outlined,
                                  color: licenseUploaded
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF0F766E),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isUploadingLicense
                                    ? 'Uploading license'
                                    : licenseUploaded
                                    ? 'Replace driver license'
                                    : 'Upload driver license',
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Required before admin approval.',
                                style: TextStyle(color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isUploadingLicense || isSaving
                  ? null
                  : () => uploadLicense(vehicle: true),
              icon: Icon(
                vehiclePhotoUrl == null
                    ? Icons.add_a_photo_outlined
                    : Icons.check_circle_outline,
              ),
              label: Text(
                vehiclePhotoUrl == null
                    ? 'Upload vehicle photo'
                    : 'Replace vehicle photo',
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: isSaving || isUploadingLicense ? null : submit,
              child: Text(
                isSaving ? 'Submitting profile...' : 'Submit for Review',
              ),
            ),
            const SizedBox(height: 10),
            if (!widget.returnToProfile)
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
