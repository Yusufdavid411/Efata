import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:logistics_app/core/services/app_notification_banner_service.dart';
import 'package:logistics_app/core/services/location_service.dart';
import 'package:logistics_app/shared/widgets/app_live_map.dart';

import '../chat/chat_screen.dart';
import 'driver_voice_navigation_screen.dart';

class DriverActiveJobsScreen extends StatefulWidget {
  const DriverActiveJobsScreen({super.key, this.initialOrderId});

  final String? initialOrderId;

  @override
  State<DriverActiveJobsScreen> createState() => _DriverActiveJobsScreenState();
}

class _DriverActiveJobsScreenState extends State<DriverActiveJobsScreen> {
  StreamSubscription<Position>? locationSubscription;
  String? trackingOrderId;

  Future<bool> startTransit(String id) async {
    final allowed = await ensureLocationPermission();
    if (!allowed) return false;

    final position = await LocationService.getCurrentPosition();

    await FirebaseFirestore.instance.collection('orders').doc(id).update({
      'status': 'inTransit',
      'startedAt': Timestamp.now(),
      'notificationStatus': 'inTransit',
      if (position != null) ...{
        'driverLat': position.latitude,
        'driverLng': position.longitude,
        'lastLocationUpdate': Timestamp.now(),
      },
    });

    startLiveLocationTracking(id);
    return true;
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
        AppNotificationBannerService.error(
          'Please turn on your location service.',
          title: 'Location needed',
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
        AppNotificationBannerService.error(
          'Location permission is required.',
          title: 'Permission needed',
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

          active.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime =
                (aData['startedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                (aData['acceptedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                (aData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                0;
            final bTime =
                (bData['startedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                (bData['acceptedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                (bData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                0;
            return bTime.compareTo(aTime);
          });

          final preferredJob = widget.initialOrderId == null
              ? null
              : active.cast<QueryDocumentSnapshot?>().firstWhere(
                  (doc) => doc?.id == widget.initialOrderId,
                  orElse: () => null,
                );
          final job = preferredJob ?? active.first;
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
          final hasRoute =
              pickupLat != null &&
              pickupLng != null &&
              dropoffLat != null &&
              dropoffLng != null;

          if (status == 'intransit') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              startLiveLocationTracking(job.id);
            });
          }

          final pickupPoint = hasRoute ? LatLng(pickupLat, pickupLng) : null;
          final dropoffPoint = hasRoute ? LatLng(dropoffLat, dropoffLng) : null;
          final driverPoint = driverLat != null && driverLng != null
              ? LatLng(driverLat, driverLng)
              : null;
          final activeTargetPoint = status == 'accepted'
              ? pickupPoint
              : dropoffPoint;
          final activeTargetLabel = status == 'accepted'
              ? 'Go to pickup'
              : 'Go to drop-off';
          final canUseVoiceNavigation =
              pickupLat != null &&
              pickupLng != null &&
              dropoffLat != null &&
              dropoffLng != null;

          void openVoiceNavigation({required bool includePickupStop}) {
            if (!canUseVoiceNavigation) {
              AppNotificationBannerService.error(
                'Voice navigation needs pickup and drop-off coordinates.',
                title: 'Route unavailable',
              );
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DriverVoiceNavigationScreen(
                  orderId: job.id,
                  pickupLabel: pickup,
                  dropoffLabel: dropoff,
                  pickupLat: pickupLat,
                  pickupLng: pickupLng,
                  dropoffLat: dropoffLat,
                  dropoffLng: dropoffLng,
                  includePickupStop: includePickupStop,
                ),
              ),
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: hasRoute
                    ? AppLiveMap(
                        pickupPoint: pickupPoint!,
                        dropoffPoint: dropoffPoint!,
                        driverPoint: driverPoint,
                        followDriver: status == 'intransit',
                        activeTargetPoint: activeTargetPoint,
                        activeTargetLabel: activeTargetLabel,
                      )
                    : const Padding(
                        padding: EdgeInsets.all(16),
                        child: _RouteMissingCard(),
                      ),
              ),
              DraggableScrollableSheet(
                initialChildSize: 0.38,
                minChildSize: 0.2,
                maxChildSize: 0.78,
                builder: (context, scrollController) {
                  return _DriverJobSheet(
                    scrollController: scrollController,
                    statusLabel: statusLabel,
                    pickup: pickup,
                    dropoff: dropoff,
                    item: item,
                    vehicleType: vehicleType,
                    scheduleLabel: scheduleLabel,
                    createdAtLabel: "Created: ${formatTime(createdAt)}",
                    priceLabel: price == null ? null : _formatPrice(price),
                    paymentLabel:
                        "$paymentMethod (${formatPaymentStatus(paymentStatus)})",
                    chatLabel: chatLabel,
                    unreadMessages: unreadMessages,
                    onChat: () {
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
                    primaryAction: status == 'accepted'
                        ? _DriverJobAction(
                            label: 'Start Voice Navigation',
                            icon: Icons.volume_up_rounded,
                            onPressed: () async {
                              final started = await startTransit(job.id);
                              if (!started || !context.mounted) return;
                              openVoiceNavigation(includePickupStop: true);
                            },
                          )
                        : _DriverJobAction(
                            label: 'Mark Completed',
                            icon: Icons.check_circle_outline,
                            onPressed: () => completeJob(job.id, data),
                          ),
                    secondaryAction: status == 'intransit'
                        ? _DriverJobAction(
                            label: 'Voice Navigation',
                            icon: Icons.navigation_rounded,
                            onPressed: () =>
                                openVoiceNavigation(includePickupStop: false),
                          )
                        : null,
                  );
                },
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

String _formatPrice(dynamic price) {
  if (price is num) return 'NGN ${price.toStringAsFixed(0)}';

  final parsed = double.tryParse(price?.toString() ?? '');
  if (parsed != null) return 'NGN ${parsed.toStringAsFixed(0)}';

  return 'NGN ${price.toString()}';
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

class _DriverJobAction {
  const _DriverJobAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class _DriverJobSheet extends StatefulWidget {
  const _DriverJobSheet({
    required this.scrollController,
    required this.statusLabel,
    required this.pickup,
    required this.dropoff,
    required this.item,
    required this.vehicleType,
    required this.scheduleLabel,
    required this.createdAtLabel,
    required this.priceLabel,
    required this.paymentLabel,
    required this.chatLabel,
    required this.unreadMessages,
    required this.onChat,
    required this.primaryAction,
    this.secondaryAction,
  });

  final ScrollController scrollController;
  final String statusLabel;
  final String pickup;
  final String dropoff;
  final String item;
  final String? vehicleType;
  final String scheduleLabel;
  final String createdAtLabel;
  final String? priceLabel;
  final String paymentLabel;
  final String chatLabel;
  final int unreadMessages;
  final VoidCallback onChat;
  final _DriverJobAction primaryAction;
  final _DriverJobAction? secondaryAction;

  @override
  State<_DriverJobSheet> createState() => _DriverJobSheetState();
}

class _DriverJobSheetState extends State<_DriverJobSheet> {
  bool showDetails = false;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Color(0x260F172A),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          Center(
            child: Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Live Delivery',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _StatusPill(label: widget.statusLabel),
            ],
          ),
          const SizedBox(height: 16),
          _RoutePoint(label: 'Pickup', value: widget.pickup),
          const SizedBox(height: 12),
          _RoutePoint(label: 'Drop-off', value: widget.dropoff),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryChip(
                icon: Icons.inventory_2_outlined,
                label: widget.item,
              ),
              if (widget.priceLabel != null)
                _SummaryChip(
                  icon: Icons.payments_outlined,
                  label: widget.priceLabel!,
                ),
              if (widget.vehicleType != null && widget.vehicleType!.isNotEmpty)
                _SummaryChip(
                  icon: Icons.local_shipping_outlined,
                  label: widget.vehicleType!,
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => showDetails = !showDetails),
            icon: Icon(
              showDetails
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
            ),
            label: Text(showDetails ? 'Hide More Details' : 'More Details'),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.schedule_rounded,
                      value: widget.scheduleLabel,
                    ),
                    const SizedBox(height: 9),
                    _InfoRow(
                      icon: Icons.event_note_outlined,
                      value: widget.createdAtLabel,
                    ),
                    const SizedBox(height: 9),
                    _InfoRow(
                      icon: Icons.account_balance_wallet_outlined,
                      value: widget.paymentLabel,
                    ),
                  ],
                ),
              ),
            ),
            crossFadeState: showDetails
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onChat,
            icon: _ChatBadge(count: widget.unreadMessages),
            label: Text(widget.chatLabel),
          ),
          const SizedBox(height: 10),
          if (widget.secondaryAction != null) ...[
            OutlinedButton.icon(
              onPressed: widget.secondaryAction!.onPressed,
              icon: Icon(widget.secondaryAction!.icon),
              label: Text(widget.secondaryAction!.label),
            ),
            const SizedBox(height: 10),
          ],
          ElevatedButton.icon(
            onPressed: widget.primaryAction.onPressed,
            icon: Icon(widget.primaryAction.icon),
            label: Text(widget.primaryAction.label),
          ),
        ],
      ),
    );
  }
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

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 38, maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF64748B), size: 17),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
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
