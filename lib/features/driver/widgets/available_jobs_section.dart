import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/efata_backend_config.dart';
import '../../../core/models/efata_api_models.dart';
import '../../../core/services/efata_api_client.dart';
import '../../../core/services/google_route_service.dart';
import '../../../core/services/app_notification_banner_service.dart';
import '../../../shared/widgets/app_live_map.dart';
import '../driver_active_jobs_screen.dart';

class AvailableJobsSection extends StatefulWidget {
  final bool isOnline;

  const AvailableJobsSection({super.key, required this.isOnline});

  @override
  State<AvailableJobsSection> createState() => _AvailableJobsSectionState();
}

class _AvailableJobsSectionState extends State<AvailableJobsSection> {
  List<QueryDocumentSnapshot> _cachedJobs = [];
  List<EfataOrder> _cachedApiJobs = const [];
  final Set<String> _hiddenApiJobs = <String>{};
  LatLng? _apiDriverPoint;
  Timer? _apiRefreshTimer;
  bool _apiLoading = false;
  Object? _apiError;

  @override
  void initState() {
    super.initState();
    if (EfataBackendConfig.useNewBackend) {
      _syncApiRefresh();
    }
  }

  @override
  void didUpdateWidget(covariant AvailableJobsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (EfataBackendConfig.useNewBackend &&
        oldWidget.isOnline != widget.isOnline) {
      _syncApiRefresh();
    }
  }

  @override
  void dispose() {
    _apiRefreshTimer?.cancel();
    super.dispose();
  }

  void _syncApiRefresh() {
    _apiRefreshTimer?.cancel();
    if (!widget.isOnline) return;
    _loadApiJobs();
    _apiRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadApiJobs(),
    );
  }

  Future<void> _loadApiJobs() async {
    if (_apiLoading || !widget.isOnline) return;
    _apiLoading = true;
    try {
      final results = await Future.wait<Object>([
        EfataApiClient.instance.getMe(),
        EfataApiClient.instance.listOrders(scope: 'available'),
      ]);
      final account = results[0] as EfataAccount;
      final page = results[1] as EfataOrderPage;
      final profile = account.driverProfile;
      final lat = _toDouble(profile?['currentLat']);
      final lng = _toDouble(profile?['currentLng']);
      if (!mounted) return;
      setState(() {
        _cachedApiJobs = page.orders
            .where((order) => !_hiddenApiJobs.contains(order.id))
            .toList(growable: false);
        _apiDriverPoint = lat != null && lng != null ? LatLng(lat, lng) : null;
        _apiError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _apiError = error);
    } finally {
      _apiLoading = false;
    }
  }

  String _normalizeStatus(dynamic value) {
    return value?.toString().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '') ??
        '';
  }

  bool _isApprovedDriver(Map<String, dynamic>? data) {
    return data?['profileCompleted'] == true &&
        data?['verificationStatus']?.toString().toLowerCase() == 'approved';
  }

  String formatPrice(dynamic price) {
    if (price == null) return "Price not available";

    if (price is num) {
      return "NGN ${price.toStringAsFixed(0)}";
    }

    final parsed = double.tryParse(price.toString());
    if (parsed != null) {
      return "NGN ${parsed.toStringAsFixed(0)}";
    }

    return "Price not available";
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  LatLng? _pointFromData(Map<String, dynamic> data, String prefix) {
    final lat = _toDouble(data['${prefix}Lat']);
    final lng = _toDouble(data['${prefix}Lng']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  Future<void> acceptJob(String orderId, String driverId) async {
    if (EfataBackendConfig.useNewBackend) {
      try {
        await EfataApiClient.instance.transitionOrder(orderId, 'accept');
        if (!mounted) return;
        AppNotificationBannerService.success(
          'Job accepted. Opening live map.',
          title: 'Job accepted',
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriverActiveJobsScreen(initialOrderId: orderId),
          ),
        );
      } on EfataApiException catch (error) {
        if (!mounted) return;
        final message = switch (error.code) {
          'current_order_active' => 'Complete your current job first.',
          'approved_online_driver_required' =>
            'Go online with an approved driver account before accepting jobs.',
          'order_unavailable' => 'Another driver has accepted this job.',
          _ => 'This job could not be accepted. Please try again.',
        };
        AppNotificationBannerService.error(
          message,
          title: error.code == 'current_order_active'
              ? 'Current job active'
              : 'Job unavailable',
        );
        await _loadApiJobs();
      }
      return;
    }

    final driverProfile = await FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .get();

    if (!_isApprovedDriver(driverProfile.data())) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        'Admin approval is required before accepting jobs.',
        title: 'Approval required',
      );
      return;
    }

    final activeJobs = await FirebaseFirestore.instance
        .collection('orders')
        .where('driverId', isEqualTo: driverId)
        .get();

    final hasActive = activeJobs.docs.any((doc) {
      final status = _normalizeStatus(doc['status']);
      return status == 'accepted' || status == 'intransit';
    });

    if (!mounted) return;

    if (hasActive) {
      AppNotificationBannerService.error(
        'Complete your current job first.',
        title: 'Current job active',
      );
      return;
    }

    var accepted = false;

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final orderRef = FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId);
      final order = await transaction.get(orderRef);
      final data = order.data();

      if (data == null ||
          data['status'] != 'pending' ||
          data['driverId'] != null) {
        return;
      }

      transaction.update(orderRef, {
        'driverId': driverId,
        'status': 'accepted',
        'acceptedAt': Timestamp.now(),
        'notificationStatus': 'driverAccepted',
        if (_toDouble(driverProfile.data()?['driverLat']) != null &&
            _toDouble(driverProfile.data()?['driverLng']) != null) ...{
          'driverLat': _toDouble(driverProfile.data()?['driverLat']),
          'driverLng': _toDouble(driverProfile.data()?['driverLng']),
          'lastLocationUpdate': Timestamp.now(),
        },
      });
      accepted = true;
    });

    if (!mounted) return;

    if (accepted) {
      AppNotificationBannerService.success(
        'Job accepted. Opening live map.',
        title: 'Job accepted',
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverActiveJobsScreen(initialOrderId: orderId),
        ),
      );
    } else {
      AppNotificationBannerService.error(
        'This job has already been accepted.',
        title: 'Job unavailable',
      );
    }
  }

  Future<void> hideJobForDriver(String orderId, String driverId) async {
    final shouldReject = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.block_rounded,
                        color: Color(0xFFEA580C),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reject this delivery?',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'This delivery will be removed from your available jobs. You may not see it again.',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('Reject Delivery'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('Keep Delivery'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldReject != true) return;

    if (EfataBackendConfig.useNewBackend) {
      setState(() {
        _hiddenApiJobs.add(orderId);
        _cachedApiJobs = _cachedApiJobs
            .where((order) => order.id != orderId)
            .toList(growable: false);
      });
      AppNotificationBannerService.info(
        'This delivery has been removed from your available jobs.',
        title: 'Delivery hidden',
        icon: Icons.visibility_off_outlined,
      );
      return;
    }

    await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      'rejectedBy': FieldValue.arrayUnion([driverId]),
    });

    if (!mounted) return;
    AppNotificationBannerService.info(
      'This delivery has been removed from your available jobs.',
      title: 'Delivery rejected',
      icon: Icons.block_rounded,
    );
  }

  void _showJobMapPreview({
    required LatLng pickupPoint,
    required LatLng dropoffPoint,
    required LatLng? driverPoint,
    required String pickup,
    required String dropoff,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Route preview',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    child: AppLiveMap(
                      pickupPoint: pickupPoint,
                      dropoffPoint: dropoffPoint,
                      driverPoint: driverPoint,
                      activeTargetPoint: pickupPoint,
                      activeTargetLabel: 'Pickup location',
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Column(
                    children: [
                      _PreviewRouteRow(label: 'Pickup', value: pickup),
                      const SizedBox(height: 10),
                      _PreviewRouteRow(label: 'Drop-off', value: dropoff),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<QueryDocumentSnapshot> _prepareJobs(
    List<QueryDocumentSnapshot> docs,
    String driverId,
  ) {
    final filtered = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      final status = data['status']?.toString() ?? '';
      final rejectedByRaw = data['rejectedBy'];
      final rejectedBy = rejectedByRaw is List ? rejectedByRaw : [];

      return status == 'pending' && !rejectedBy.contains(driverId);
    }).toList();

    filtered.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;

      final aTime =
          (aData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final bTime =
          (bData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

      return bTime.compareTo(aTime); // newest first
    });

    return filtered;
  }

  Widget _buildOfflineNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "You are offline. You can still view already loaded jobs, but you will not receive the latest available jobs until you go online again.",
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(
    BuildContext context,
    String jobId,
    Map<String, dynamic> data,
    String driverId,
    LatLng? driverPoint,
  ) {
    final pickup = data['pickup']?.toString() ?? 'No pickup location';
    final dropoff = data['dropoff']?.toString() ?? 'No drop-off location';
    final item = data['item']?.toString() ?? 'No item description';
    final vehicleType = data['vehicleType']?.toString();
    final price = data['price'];
    final pickupPoint = _pointFromData(data, 'pickup');
    final dropoffPoint = _pointFromData(data, 'dropoff');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFFDF6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.local_shipping_outlined,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pickup,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Icon(
                          Icons.arrow_downward_rounded,
                          color: Color(0xFF94A3B8),
                          size: 17,
                        ),
                      ),
                      Text(
                        dropoff,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              item,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _JobChip(
                  icon: Icons.payments_outlined,
                  label: formatPrice(price),
                  tone: const Color(0xFF16A34A),
                ),
                if (vehicleType != null && vehicleType.isNotEmpty)
                  _JobChip(
                    icon: Icons.local_shipping_outlined,
                    label: vehicleType,
                    tone: const Color(0xFF475569),
                  ),
                if (pickupPoint != null && dropoffPoint != null)
                  _RouteEtaChipGroup(
                    driverPoint: driverPoint,
                    pickupPoint: pickupPoint,
                    dropoffPoint: dropoffPoint,
                  ),
              ],
            ),
            if (pickupPoint != null && dropoffPoint != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => _showJobMapPreview(
                  pickupPoint: pickupPoint,
                  dropoffPoint: dropoffPoint,
                  driverPoint: driverPoint,
                  pickup: pickup,
                  dropoff: dropoff,
                ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('View route'),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await acceptJob(jobId, driverId);
                    },
                    child: const Text("Accept"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await hideJobForDriver(jobId, driverId);
                    },
                    child: const Text("Reject"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobList(BuildContext context, String driverId) {
    if (_cachedJobs.isEmpty) {
      return const Text("No available jobs");
    }

    return Column(
      children: _cachedJobs.map((job) {
        return _buildJobCard(
          context,
          job.id,
          job.data() as Map<String, dynamic>,
          driverId,
          null,
        );
      }).toList(),
    );
  }

  Widget _buildJobListWithDriverPoint(
    BuildContext context,
    String driverId,
    LatLng? driverPoint,
  ) {
    if (_cachedJobs.isEmpty) {
      return const Text("No available jobs");
    }

    return Column(
      children: _cachedJobs.map((job) {
        return _buildJobCard(
          context,
          job.id,
          job.data() as Map<String, dynamic>,
          driverId,
          driverPoint,
        );
      }).toList(),
    );
  }

  Widget _buildApiJobs(String driverId) {
    if (!widget.isOnline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOfflineNotice(),
          if (_cachedApiJobs.isEmpty)
            const Text('Go online to load available jobs')
          else
            ..._cachedApiJobs.map(
              (order) => _buildJobCard(
                context,
                order.id,
                order.toLegacyMap(),
                driverId,
                _apiDriverPoint,
              ),
            ),
        ],
      );
    }
    if (_apiLoading && _cachedApiJobs.isEmpty && _apiError == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_apiError != null && _cachedApiJobs.isEmpty) {
      return _AvailableJobsError(onRetry: _loadApiJobs);
    }
    if (_cachedApiJobs.isEmpty) {
      return const Text('No available jobs');
    }
    return Column(
      children: _cachedApiJobs
          .map(
            (order) => _buildJobCard(
              context,
              order.id,
              order.toLegacyMap(),
              driverId,
              _apiDriverPoint,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) {
      return const Text("Driver not logged in");
    }

    if (EfataBackendConfig.useNewBackend) {
      return _buildApiJobs(driver.uid);
    }

    if (!widget.isOnline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildOfflineNotice(), _buildJobList(context, driver.uid)],
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('drivers')
          .doc(driver.uid)
          .snapshots(),
      builder: (context, driverSnapshot) {
        final driverData = driverSnapshot.data?.data() as Map<String, dynamic>?;
        final driverLat = _toDouble(driverData?['driverLat']);
        final driverLng = _toDouble(driverData?['driverLng']);
        final driverPoint = driverLat != null && driverLng != null
            ? LatLng(driverLat, driverLng)
            : null;

        if (driverSnapshot.hasData && !_isApprovedDriver(driverData)) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Text(
              "Jobs will appear here after your driver account is approved.",
            ),
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('status', isEqualTo: 'pending')
              .where('driverId', isNull: true)
              .limit(25)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                _cachedJobs.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Text("Something went wrong: ${snapshot.error}");
            }

            if (snapshot.hasData) {
              _cachedJobs = _prepareJobs(snapshot.data!.docs, driver.uid);
            }

            return _buildJobListWithDriverPoint(
              context,
              driver.uid,
              driverPoint,
            );
          },
        );
      },
    );
  }
}

class _AvailableJobsError extends StatelessWidget {
  const _AvailableJobsError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFDC2626)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Available jobs could not load.',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: onRetry,
            tooltip: 'Retry',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _RouteEtaChipGroup extends StatelessWidget {
  const _RouteEtaChipGroup({
    required this.driverPoint,
    required this.pickupPoint,
    required this.dropoffPoint,
  });

  final LatLng? driverPoint;
  final LatLng pickupPoint;
  final LatLng dropoffPoint;

  String _formatDuration(int minutes) {
    if (minutes <= 0) return 'Time unavailable';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    final hourLabel = hours == 1 ? '1hr' : '${hours}hrs';
    return remainder == 0 ? hourLabel : '$hourLabel ${remainder}min';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GoogleRouteResult?>>(
      future: Future.wait([
        if (driverPoint != null)
          GoogleRouteService.routeBetween(
            pickup: driverPoint!,
            dropoff: pickupPoint,
            cachePrecision: 4,
          )
        else
          Future<GoogleRouteResult?>.value(null),
        GoogleRouteService.routeBetween(
          pickup: pickupPoint,
          dropoff: dropoffPoint,
          cachePrecision: 4,
        ),
      ]),
      builder: (context, snapshot) {
        final toPickup = snapshot.data?[0];
        final toDropoff = snapshot.data?[1];

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _JobChip(
              icon: Icons.near_me_outlined,
              label: toPickup == null
                  ? 'Pickup ETA pending'
                  : 'Pickup ${_formatDuration(toPickup.durationMinutes)}',
              tone: const Color(0xFF2563EB),
            ),
            _JobChip(
              icon: Icons.route_outlined,
              label: toDropoff == null
                  ? 'Trip ETA pending'
                  : 'Trip ${_formatDuration(toDropoff.durationMinutes)}',
              tone: const Color(0xFF7C3AED),
            ),
          ],
        );
      },
    );
  }
}

class _JobChip extends StatelessWidget {
  const _JobChip({required this.icon, required this.label, required this.tone});

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRouteRow extends StatelessWidget {
  const _PreviewRouteRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          label == 'Pickup' ? Icons.inventory_2_outlined : Icons.flag_outlined,
          color: const Color(0xFF0F766E),
          size: 19,
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
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
