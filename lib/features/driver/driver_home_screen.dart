import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:logistics_app/core/services/app_notification_banner_service.dart';
import 'package:logistics_app/core/services/efata_api_client.dart';
import 'package:logistics_app/core/services/efata_session.dart';
import 'package:logistics_app/core/services/location_service.dart';

import '../../shared/widgets/app_bottom_navigation.dart';
import 'driver_jobs_screen.dart';
import 'driver_profile_screen.dart';
import 'widgets/driver_status_toggle.dart';
import 'widgets/available_jobs_section.dart';
import 'widgets/driver_current_job_card.dart';
import 'widgets/driver_earnings_summary.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool isOnline = false;
  bool isLoadingAvailability = true;
  int currentIndex = 0;
  String verificationStatus = 'incomplete';
  bool profileCompleted = false;
  StreamSubscription<Position>? driverLocationSubscription;
  DateTime? _lastApiLocationPushAt;
  Timer? _availabilityRefresh;
  int _availabilityRequest = 0;
  Position? _mapPosition;
  GoogleMapController? _dashboardMap;
  bool _changingAvailability = false;
  final _profileEarningsKey = GlobalKey();

  void _openEarnings() {
    setState(() => currentIndex = 2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final earnings = _profileEarningsKey.currentContext;
      if (earnings != null) {
        unawaited(
          Scrollable.ensureVisible(
            earnings,
            duration: const Duration(milliseconds: 220),
          ),
        );
      }
    });
  }

  LatLng? get _driverPoint {
    final position = _mapPosition;
    return isOnline && position != null
        ? LatLng(position.latitude, position.longitude)
        : null;
  }

  void _centerMap() {
    final point = _driverPoint;
    final map = _dashboardMap;
    if (point != null && map != null) {
      unawaited(map.animateCamera(CameraUpdate.newLatLngZoom(point, 16)));
    }
  }

  @override
  void initState() {
    super.initState();
    loadDriverAvailability();
    _availabilityRefresh = Timer.periodic(const Duration(seconds: 10), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          !isLoadingAvailability) {
        unawaited(_loadApiDriverAvailability(quiet: true));
      }
    });
  }

  void loadDriverAvailability() => unawaited(_loadApiDriverAvailability());

  Future<void> _loadApiDriverAvailability({bool quiet = false}) async {
    final request = ++_availabilityRequest;
    try {
      final account = await EfataApiClient.instance.getMe();
      final profile = account.driverProfile;
      final savedStatus = profile?['isOnline'] == true;
      if (!mounted || request != _availabilityRequest) return;
      final status = profile?['verificationStatus']?.toString() ?? 'incomplete';
      final justApproved =
          !isLoadingAvailability &&
          verificationStatus != 'approved' &&
          status == 'approved';
      final onlineChanged = isOnline != savedStatus;
      setState(() {
        isOnline = savedStatus;
        if (!savedStatus) _mapPosition = null;
        verificationStatus = status;
        profileCompleted = account.profileCompleted;
        isLoadingAvailability = false;
      });
      if (onlineChanged) _syncOnlineLocationTracking(savedStatus);
      if (justApproved) {
        AppNotificationBannerService.success(
          'You can now go online and receive jobs.',
          title: 'Driver approved',
        );
      }
    } catch (_) {
      if (!mounted || request != _availabilityRequest || quiet) return;
      setState(() => isLoadingAvailability = false);
      AppNotificationBannerService.error(
        'Driver status could not load. Pull down or reopen the dashboard to retry.',
        title: 'Status unavailable',
      );
    }
  }

  Future<void> handleStatusChange(bool value) async {
    if (_changingAvailability) return;
    setState(() => _changingAvailability = true);
    try {
      await _changeAvailability(value);
    } finally {
      if (mounted) setState(() => _changingAvailability = false);
    }
  }

  Future<void> _changeAvailability(bool value) async {
    final driver = EfataSession.instance.accountUid;

    if (driver == null) return;

    if (value && verificationStatus != 'approved') {
      await _loadApiDriverAvailability(quiet: true);
      if (!mounted) return;
    }
    if (value && verificationStatus.toLowerCase() != 'approved') {
      AppNotificationBannerService.error(
        !profileCompleted
            ? 'Complete your driver profile before going online.'
            : 'Your account must be approved before receiving jobs.',
        title: 'Driver not verified',
      );
      return;
    }

    if (!value) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Go Offline?"),
          content: const Text("You won't receive new jobs while offline."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Go Offline"),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    Position? currentPosition;
    if (value) {
      currentPosition = await _prepareDriverLocation();
      if (currentPosition == null || !mounted) return;
    }

    try {
      await EfataApiClient.instance.setDriverAvailability(
        online: value,
        lat: currentPosition?.latitude,
        lng: currentPosition?.longitude,
        heading: currentPosition?.heading,
      );

      if (!mounted) return;
      ++_availabilityRequest;
      setState(() {
        isOnline = value;
        _mapPosition = currentPosition;
      });
      _centerMap();
      _syncOnlineLocationTracking(value);
      AppNotificationBannerService.success(
        value
            ? 'You are now receiving delivery requests.'
            : 'You will not receive new jobs while offline.',
        title: value ? 'You are online' : 'You are offline',
      );
    } catch (_) {
      AppNotificationBannerService.error(
        'Network issue. Please try updating your status again.',
      );
    }
  }

  Future<Position?> _prepareDriverLocation() async {
    final access = await LocationService.requestLocationAccess();

    if (access == LocationAccessStatus.serviceDisabled) {
      AppNotificationBannerService.error(
        'Turn on location so passengers can track their delivery.',
        title: 'Location required',
      );
      await LocationService.openLocationSettings();
      return null;
    }

    if (access == LocationAccessStatus.deniedForever) {
      AppNotificationBannerService.error(
        'Allow location permission from app settings before going online.',
        title: 'Permission required',
      );
      await LocationService.openAppSettings();
      return null;
    }

    if (access != LocationAccessStatus.granted) {
      AppNotificationBannerService.error(
        'Location permission is required before you can receive jobs.',
        title: 'Location required',
      );
      return null;
    }

    final position = await LocationService.getCurrentPosition();
    if (position == null) {
      AppNotificationBannerService.error(
        'EFATA could not read your current location. Please try again.',
        title: 'Location unavailable',
      );
    }
    return position;
  }

  Future<void> _syncOnlineLocationTracking(bool shouldTrack) async {
    final driver = EfataSession.instance.accountUid;
    if (driver == null) return;

    if (!shouldTrack) {
      final subscription = driverLocationSubscription;
      driverLocationSubscription = null;
      await subscription?.cancel();
      return;
    }

    if (driverLocationSubscription != null) return;

    final access = await LocationService.requestLocationAccess();
    if (access != LocationAccessStatus.granted ||
        !mounted ||
        !isOnline ||
        driverLocationSubscription != null) {
      return;
    }

    driverLocationSubscription = LocationService.getLiveLocationStream().listen(
      (position) {
        if (!mounted || !isOnline) return;
        if (_mapPosition == null) {
          setState(() => _mapPosition = position);
          _centerMap();
        } else {
          _mapPosition = position;
        }
        final now = DateTime.now();
        final lastPush = _lastApiLocationPushAt;
        if (lastPush != null && now.difference(lastPush).inSeconds < 5) {
          return;
        }
        _lastApiLocationPushAt = now;
        unawaited(_pushApiLocation(position));
      },
    );
  }

  Future<void> _pushApiLocation(Position position) async {
    try {
      await EfataApiClient.instance.updateDriverLocation(
        lat: position.latitude,
        lng: position.longitude,
        heading: position.heading,
      );
    } catch (_) {
      _lastApiLocationPushAt = null;
    }
  }

  @override
  void dispose() {
    _availabilityRefresh?.cancel();
    driverLocationSubscription?.cancel();
    super.dispose();
  }

  Widget verificationCard() {
    if (isLoadingAvailability) return const SizedBox.shrink();

    final status = verificationStatus.toLowerCase();
    final approved = status == 'approved';

    if (approved) return const SizedBox.shrink();

    final color = approved
        ? Colors.green
        : status == 'pending'
        ? Colors.orange
        : Colors.red;
    final title = !profileCompleted
        ? 'Complete driver profile'
        : status == 'pending'
        ? 'Awaiting review'
        : 'Driver approval required';
    final message = !profileCompleted
        ? 'Add your vehicle and contact details so admin can verify your account.'
        : status == 'pending'
        ? 'Your documents were received. Allow 24 to 48 hours for review.'
        : 'Your account must be approved before you can receive delivery requests.';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: !profileCompleted
              ? () => Navigator.pushNamed(context, '/driverOnboarding')
              : null,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.shade50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.shade100,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    approved
                        ? Icons.verified_user_outlined
                        : Icons.pending_actions_outlined,
                    color: color.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: color.shade900,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          height: 1.35,
                        ),
                      ),
                      if (!profileCompleted) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              'Continue setup',
                              style: TextStyle(
                                color: color.shade800,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: color.shade800,
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget dashboardTab() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final approved = verificationStatus == 'approved';
    return RefreshIndicator(
      onRefresh: _loadApiDriverAvailability,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          if (isLoadingAvailability)
            const LinearProgressIndicator()
          else ...[
            DriverStatusToggle(
              isOnline: isOnline,
              isLoading: _changingAvailability,
              canGoOnline: approved,
              onChanged: handleStatusChange,
            ),
            verificationCard(),
          ],
          const SizedBox(height: 16),
          DriverEarningsSummary(compact: true, onOpenDetails: _openEarnings),
          const SizedBox(height: 16),
          const DriverCurrentJobCard(),
          if (isOnline)
            SizedBox(
              height: 176,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _driverPoint ?? const LatLng(9.08, 8.68),
                        zoom: _driverPoint == null ? 5.5 : 16,
                      ),
                      onMapCreated: (map) {
                        _dashboardMap = map;
                        _centerMap();
                      },
                      myLocationEnabled: _driverPoint != null,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                    ),
                  ),
                  if (_driverPoint != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton.filledTonal(
                        tooltip: 'Center on my location',
                        onPressed: _centerMap,
                        icon: const Icon(Icons.my_location),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Text('Available jobs', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          if (!isLoadingAvailability)
            AvailableJobsSection(isOnline: isOnline, canGoOnline: approved)
          else
            Text(
              'Checking availability',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: currentIndex == 0
          ? AppBar(title: const Text('EFATA'), automaticallyImplyLeading: false)
          : currentIndex == 1
          ? AppBar(title: const Text('Jobs'), automaticallyImplyLeading: false)
          : null,
      bottomNavigationBar: AppBottomNavigation(
        isDriver: true,
        currentIndex: currentIndex,
        onDestinationSelected: (index) => setState(() => currentIndex = index),
      ),
      body: IndexedStack(
        index: currentIndex,
        children: [
          dashboardTab(),
          const DriverJobsContent(),
          SafeArea(
            bottom: false,
            child: DriverProfileScreen(
              embedded: true,
              earningsKey: _profileEarningsKey,
              onOpenJobs: () => setState(() => currentIndex = 1),
            ),
          ),
        ],
      ),
    );
  }
}
