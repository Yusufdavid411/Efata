import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chat/chat_screen.dart';

class DriverActiveJobsScreen extends StatefulWidget {
  const DriverActiveJobsScreen({super.key});

  @override
  State<DriverActiveJobsScreen> createState() => _DriverActiveJobsScreenState();
}

class _DriverActiveJobsScreenState extends State<DriverActiveJobsScreen> {
  StreamSubscription<Position>? locationSubscription;
  String? trackingOrderId;

  Future<void> startTransit(String id) async {
    await FirebaseFirestore.instance.collection('orders').doc(id).update({
      'status': 'inTransit',
      'startedAt': Timestamp.now(),
      'notificationStatus': 'inTransit',
    });

    startLiveLocationTracking(id);
  }

  Future<void> completeJob(String id, Map<String, dynamic> data) async {
    final currentPaymentStatus =
        data['paymentStatus']?.toString().toLowerCase() ?? 'pending';
    bool paymentReceived = [
      'paid',
      'customersent',
    ].contains(currentPaymentStatus);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Complete Delivery?"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Confirm that the goods have been delivered to the customer.",
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: paymentReceived,
                    title: const Text("Payment received"),
                    onChanged: (value) {
                      setDialogState(() => paymentReceived = value ?? false);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text("Confirm"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    await locationSubscription?.cancel();
    locationSubscription = null;
    trackingOrderId = null;

    await FirebaseFirestore.instance.collection('orders').doc(id).update({
      'status': 'completed',
      'completedAt': Timestamp.now(),
      'deliveryCompletedConfirmed': true,
      'notificationStatus': 'completed',
      'paymentStatus': paymentReceived
          ? 'paid'
          : data['paymentStatus'] ?? 'pending',
      'paymentConfirmedAt': paymentReceived ? Timestamp.now() : null,
      if (!paymentReceived) ...{
        'paymentReviewRequired': true,
        'paymentIssue': 'Delivery completed without confirmed payment',
        'paymentIssueOpenedBy': 'driver',
        'paymentIssueOpenedAt': Timestamp.now(),
        'needsAdminReview': true,
      },
    });
  }

  String formatPaymentStatus(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return 'Paid';
      case 'customersent':
        return 'Customer Sent';
      case 'cashdue':
        return 'Cash Due';
      case 'pending':
        return 'Pending';
      default:
        return status;
    }
  }

  Future<bool> ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please turn on your location service")),
        );
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission is required")),
        );
      }
      return false;
    }

    return true;
  }

  Future<void> startLiveLocationTracking(String orderId) async {
    if (trackingOrderId == orderId && locationSubscription != null) return;

    final allowed = await ensureLocationPermission();
    if (!allowed) return;

    await locationSubscription?.cancel();

    trackingOrderId = orderId;

    locationSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((position) {
          FirebaseFirestore.instance.collection('orders').doc(orderId).update({
            'driverLat': position.latitude,
            'driverLng': position.longitude,
            'lastLocationUpdate': Timestamp.now(),
          });
        });
  }

  String formatTime(dynamic ts) {
    if (ts == null || ts is! Timestamp) return 'Not available';

    final d = ts.toDate();
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');

    return "${d.day}/${d.month}/${d.year} at $hour:$minute";
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Future<void> openTurnByTurnNavigation(Map<String, dynamic> data) async {
    final pickupLat = _toDouble(data['pickupLat']);
    final pickupLng = _toDouble(data['pickupLng']);
    final dropoffLat = _toDouble(data['dropoffLat']);
    final dropoffLng = _toDouble(data['dropoffLng']);
    final status = data['status']?.toString() ?? 'accepted';

    if (pickupLat == null ||
        pickupLng == null ||
        dropoffLat == null ||
        dropoffLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Route location data is missing")),
      );
      return;
    }

    final destination = status == 'accepted'
        ? '$pickupLat,$pickupLng'
        : '$dropoffLat,$dropoffLng';

    final uri = Uri.parse('google.navigation:q=$destination&mode=d');

    final fallbackUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=driving',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Current Job")),
        body: const Center(child: Text("Driver not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Current Job"), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('driverId', isEqualTo: driver.uid)
            .limit(25)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          final active = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'];
            return status == 'accepted' || status == 'inTransit';
          }).toList();

          if (active.isEmpty) {
            return const Center(child: Text("No active job"));
          }

          final job = active.first;
          final data = job.data() as Map<String, dynamic>;

          final pickup = data['pickup']?.toString() ?? 'No pickup';
          final dropoff = data['dropoff']?.toString() ?? 'No drop-off';
          final item = data['item']?.toString() ?? 'No item';
          final status = data['status']?.toString() ?? 'accepted';
          final vehicleType = data['vehicleType']?.toString();
          final price = data['price'];
          final paymentMethod =
              data['paymentMethod']?.toString() ?? 'Cash on Delivery';
          final paymentStatus = data['paymentStatus']?.toString() ?? 'pending';
          final unreadMessages =
              (data['unreadForDriver'] as num?)?.toInt() ?? 0;
          final lastMessageSenderRole =
              data['lastMessageSenderRole']?.toString() ?? '';
          final chatLabel = _chatButtonLabel(
            unreadMessages,
            lastMessageSenderRole,
            'driver',
          );
          final createdAt = data['createdAt'];

          if (status == 'inTransit') {
            startLiveLocationTracking(job.id);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Delivery Details",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 16),

                      Text("Pickup: $pickup"),
                      const SizedBox(height: 8),
                      Text("Drop-off: $dropoff"),
                      const SizedBox(height: 8),
                      Text("Item: $item"),
                      if (vehicleType != null && vehicleType.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text("Vehicle: $vehicleType"),
                      ],
                      const SizedBox(height: 8),
                      Text("Status: $status"),
                      const SizedBox(height: 8),
                      Text("Created: ${formatTime(createdAt)}"),

                      if (price != null) ...[
                        const SizedBox(height: 8),
                        Text("Price: NGN $price"),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        "Payment: $paymentMethod (${formatPaymentStatus(paymentStatus)})",
                      ),

                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  orderId: job.id,
                                  participantRole: 'driver',
                                ),
                              ),
                            );
                          },
                          icon: _ChatBadge(count: unreadMessages),
                          label: Text(chatLabel),
                        ),
                      ),

                      const SizedBox(height: 10),

                      if (status == 'accepted')
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => openTurnByTurnNavigation(data),
                                icon: const Icon(Icons.navigation_outlined),
                                label: const Text("Navigate to Pickup"),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => startTransit(job.id),
                                child: const Text("Start Transit"),
                              ),
                            ),
                          ],
                        ),

                      if (status == 'inTransit')
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => openTurnByTurnNavigation(data),
                                icon: const Icon(Icons.navigation_outlined),
                                label: const Text("Navigate to Drop-off"),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => completeJob(job.id, data),
                                child: const Text("Mark Completed"),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _chatButtonLabel(
  int unreadMessages,
  String lastMessageSenderRole,
  String viewerRole,
) {
  if (unreadMessages == 1) return '1 new message';
  if (unreadMessages > 1) return '$unreadMessages new messages';
  if (lastMessageSenderRole == viewerRole) return 'Message sent';
  if (lastMessageSenderRole.isNotEmpty) return 'Chat updated';
  return 'Chat With Customer';
}

class _ChatBadge extends StatelessWidget {
  const _ChatBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const Icon(Icons.chat_bubble_outline_rounded);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.chat_bubble_outline_rounded),
        Positioned(
          right: -9,
          top: -9,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(
              color: Color(0xFFDC2626),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              count > 9 ? '9+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
