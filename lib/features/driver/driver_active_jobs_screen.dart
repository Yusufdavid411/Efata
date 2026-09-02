import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:logistics_app/shared/widgets/app_live_map.dart';

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
            final status = _normalizeStatus(data['status']);
            return status == 'accepted' || status == 'intransit';
          }).toList();

          if (active.isEmpty) {
            return const Center(child: Text("No active job"));
          }

          final job = active.first;
          final data = job.data() as Map<String, dynamic>;

          final pickup = data['pickup']?.toString() ?? 'No pickup';
          final dropoff = data['dropoff']?.toString() ?? 'No drop-off';
          final item = data['item']?.toString() ?? 'No item';
          final status = _normalizeStatus(data['status']);
          final statusLabel = _statusLabel(status);
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
          final scheduleLabel =
              data['pickupScheduleLabel']?.toString() ?? 'Pickup now';
          final pickupLat = _toDouble(data['pickupLat']);
          final pickupLng = _toDouble(data['pickupLng']);
          final dropoffLat = _toDouble(data['dropoffLat']);
          final dropoffLng = _toDouble(data['dropoffLng']);
          final driverLat = _toDouble(data['driverLat']);
          final driverLng = _toDouble(data['driverLng']);
          final hasRoute = pickupLat != null &&
              pickupLng != null &&
              dropoffLat != null &&
              dropoffLng != null;

          if (status == 'intransit') {
            startLiveLocationTracking(job.id);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (hasRoute)
                SizedBox(
                  height: 330,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AppLiveMap(
                      pickupPoint: LatLng(pickupLat, pickupLng),
                      dropoffPoint: LatLng(dropoffLat, dropoffLng),
                      driverPoint: driverLat != null && driverLng != null
                          ? LatLng(driverLat, driverLng)
                          : null,
                    ),
                  ),
                )
              else
                const _RouteMissingCard(),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              "Delivery Details",
                              style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _StatusPill(label: statusLabel),
                        ],
                      ),

                      const SizedBox(height: 16),

                      _RoutePoint(label: "Pickup", value: pickup),
                      const SizedBox(height: 12),
                      _RoutePoint(label: "Drop-off", value: dropoff),
                      const SizedBox(height: 14),
                      _InfoRow(icon: Icons.inventory_2_outlined, value: item),
                      if (vehicleType != null && vehicleType.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _InfoRow(
                          icon: Icons.local_shipping_outlined,
                          value: vehicleType,
                        ),
                      ],
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.schedule_rounded,
                        value: scheduleLabel,
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.event_note_outlined,
                        value: "Created: ${formatTime(createdAt)}",
                      ),

                      if (price != null) ...[
                        const SizedBox(height: 8),
                        _InfoRow(
                          icon: Icons.payments_outlined,
                          value: "NGN $price",
                        ),
                      ],
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.account_balance_wallet_outlined,
                        value:
                            "$paymentMethod (${formatPaymentStatus(paymentStatus)})",
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
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => startTransit(job.id),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text("Start Transit"),
                          ),
                        ),

                      if (status == 'intransit')
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => completeJob(job.id, data),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text("Mark Completed"),
                          ),
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

String _normalizeStatus(dynamic value) {
  return value?.toString().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '') ??
      'accepted';
}

String _statusLabel(String status) {
  switch (status) {
    case 'accepted':
      return 'Accepted';
    case 'intransit':
      return 'In Transit';
    default:
      return status;
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF166534),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RoutePoint extends StatelessWidget {
  const _RoutePoint({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFEFFDF6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            label == 'Pickup'
                ? Icons.radio_button_checked_rounded
                : Icons.location_on_rounded,
            color: const Color(0xFF0F766E),
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF64748B), size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _RouteMissingCard extends StatelessWidget {
  const _RouteMissingCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFFBEB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFFDE68A)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.map_outlined, color: Color(0xFFD97706)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Map route is unavailable because this job is missing pickup or drop-off coordinates.',
                style: TextStyle(
                  color: Color(0xFF92400E),
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
