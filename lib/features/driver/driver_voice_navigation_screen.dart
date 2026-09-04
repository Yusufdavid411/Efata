import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:logistics_app/core/services/location_service.dart';
import 'package:logistics_app/core/services/voice_navigation_control_service.dart';

class DriverVoiceNavigationScreen extends StatefulWidget {
  const DriverVoiceNavigationScreen({
    super.key,
    required this.orderId,
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.includePickupStop,
  });

  final String orderId;
  final String pickupLabel;
  final String dropoffLabel;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final bool includePickupStop;

  @override
  State<DriverVoiceNavigationScreen> createState() =>
      _DriverVoiceNavigationScreenState();
}

class _DriverVoiceNavigationScreenState
    extends State<DriverVoiceNavigationScreen> {
  GoogleNavigationViewController? _controller;
  StreamSubscription<RoadSnappedLocationUpdatedEvent>? _locationSubscription;
  StreamSubscription<void>? _reroutingSubscription;
  StreamSubscription<OnArrivalEvent>? _arrivalSubscription;
  StreamSubscription<RemainingTimeOrDistanceChangedEvent>? _etaSubscription;

  bool _sessionReady = false;
  bool _guidanceRunning = false;
  bool _routeFailed = false;
  bool _promptVisible = false;
  bool _pickupReached = false;
  bool _disposed = false;
  bool _keepRunningAfterClose = false;
  bool _stoppingNavigation = false;
  bool _stopRequested = false;
  bool _reviewingGoogleNotice = false;
  bool _voicePanelExpanded = false;
  String _message = 'Preparing voice navigation';
  double? _remainingDistanceMeters;
  double? _remainingTimeSeconds;
  DateTime? _lastLocationWrite;
  MapType _mapType = MapType.hybrid;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareNavigation());
  }

  Future<void> _prepareNavigation() async {
    final access = await LocationService.requestLocationAccess();
    if (access != LocationAccessStatus.granted) {
      _setFailure(_locationAccessMessage(access));
      return;
    }

    try {
      final termsAccepted = await _confirmNavigationTerms();

      if (!termsAccepted) {
        if (mounted) Navigator.pop(context);
        return;
      }

      await GoogleMapsNavigator.initializeNavigationSession(
        taskRemovedBehavior: TaskRemovedBehavior.quitService,
      );
      await GoogleMapsNavigator.setAudioGuidance(
        NavigationAudioGuidanceSettings(
          guidanceType: NavigationAudioGuidanceType.alertsAndGuidance,
          isBluetoothAudioEnabled: true,
          isVibrationEnabled: true,
        ),
      );
      await _setupListeners();

      if (!mounted) return;
      setState(() {
        _sessionReady = true;
        _message = 'Finding the best road route';
      });
    } on SessionInitializationException catch (error) {
      _setFailure(_sessionErrorMessage(error.code));
    } catch (error) {
      _setFailure(
        'Voice navigation could not start. Please check the map key.',
      );
      return;
    }

    await _startGuidanceWithRetry();
  }

  Future<bool> _confirmNavigationTerms() async {
    if (await GoogleMapsNavigator.areTermsAccepted()) return true;
    if (!mounted) return false;

    setState(() {
      _reviewingGoogleNotice = true;
      _message = 'Review the Google navigation notice';
    });

    try {
      return await GoogleMapsNavigator.showTermsAndConditionsDialog(
        'EFATA voice navigation',
        'EFATA',
        uiParams: const TermsAndConditionsUIParams(
          backgroundColor: Colors.white,
          titleColor: Color(0xFF0F766E),
          mainTextColor: Color(0xFF334155),
          acceptButtonTextColor: Color(0xFF0F766E),
          cancelButtonTextColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _reviewingGoogleNotice = false);
      }
    }
  }

  Future<void> _setupListeners() async {
    await _clearListeners();

    _locationSubscription =
        await GoogleMapsNavigator.setRoadSnappedLocationUpdatedListener(
          _onRoadSnappedLocation,
        );
    _reroutingSubscription = GoogleMapsNavigator.setOnReroutingListener(() {
      if (!mounted) return;
      setState(() => _message = 'Rerouting to the best available road');
    });
    _arrivalSubscription = GoogleMapsNavigator.setOnArrivalListener(
      _handleArrival,
    );
    _etaSubscription =
        GoogleMapsNavigator.setOnRemainingTimeOrDistanceChangedListener(
          (event) {
            if (!mounted) return;
            setState(() {
              _remainingDistanceMeters = event.remainingDistance;
              _remainingTimeSeconds = event.remainingTime;
            });
          },
          remainingDistanceThresholdMeters: 50,
          remainingTimeThresholdSeconds: 30,
        );
  }

  Future<void> _startGuidanceWithRetry() async {
    if (!mounted) return;
    setState(() {
      _routeFailed = false;
      _message = 'Finding the best road route';
    });

    NavigationRouteStatus status = NavigationRouteStatus.locationUnavailable;

    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        status = await GoogleMapsNavigator.setDestinations(_destinations);
        if (status == NavigationRouteStatus.statusOk) break;

        final shouldRetry =
            status == NavigationRouteStatus.locationUnavailable ||
            status == NavigationRouteStatus.locationUnknown;
        if (!shouldRetry) break;
        await Future.delayed(const Duration(seconds: 3));
      }
    } catch (_) {
      _setFailure('Voice navigation could not prepare the route. Try again.');
      return;
    }

    if (status != NavigationRouteStatus.statusOk) {
      _setFailure(_routeStatusMessage(status));
      return;
    }

    try {
      await GoogleMapsNavigator.startGuidance();
    } catch (_) {
      _setFailure('Voice navigation could not start. Please try again.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _guidanceRunning = true;
      _routeFailed = false;
      _voicePanelExpanded = false;
      _message = widget.includePickupStop
          ? 'Voice guidance to pickup has started'
          : 'Voice guidance to drop-off has started';
    });

    unawaited(_markVoiceNavigationRunning());
    unawaited(_enableNavigationUi());
  }

  Future<void> _markVoiceNavigationRunning() async {
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .set({
            'voiceNavigationStatus': 'running',
            'voiceNavigationStartedAt': Timestamp.now(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Guidance is already running; a slow status write should not show a false error.
    }
  }

  Future<void> _enableNavigationUi() async {
    try {
      await _controller?.setNavigationUIEnabled(true);
      await _controller?.followMyLocation(
        CameraPerspective.tilted,
        zoomLevel: 17,
      );
    } catch (_) {
      // The native navigation UI can still keep guiding even if one view command fails.
    }
  }

  Destinations get _destinations {
    final waypoints = <NavigationWaypoint>[];

    if (widget.includePickupStop && !_pickupReached) {
      waypoints.add(
        NavigationWaypoint.withLatLngTarget(
          title: 'Pickup: ${widget.pickupLabel}',
          target: LatLng(
            latitude: widget.pickupLat,
            longitude: widget.pickupLng,
          ),
        ),
      );
    }

    waypoints.add(
      NavigationWaypoint.withLatLngTarget(
        title: 'Drop-off: ${widget.dropoffLabel}',
        target: LatLng(
          latitude: widget.dropoffLat,
          longitude: widget.dropoffLng,
        ),
      ),
    );

    return Destinations(
      waypoints: waypoints,
      displayOptions: NavigationDisplayOptions(showDestinationMarkers: true),
      routingOptions: RoutingOptions(
        alternateRoutesStrategy: NavigationAlternateRoutesStrategy.one,
        routingStrategy: NavigationRoutingStrategy.defaultBest,
        travelMode: NavigationTravelMode.driving,
        locationTimeoutMs: 15000,
      ),
    );
  }

  Future<void> _onViewCreated(GoogleNavigationViewController controller) async {
    _controller = controller;
    await controller.setMapType(mapType: _mapType);
    await controller.setMyLocationEnabled(true);
    await controller.settings.setZoomControlsEnabled(true);
    await controller.settings.setCompassEnabled(true);
    await controller.setSpeedometerEnabled(true);
    await controller.setSpeedLimitIconEnabled(true);
    await controller.followMyLocation(CameraPerspective.tilted, zoomLevel: 17);
  }

  Future<void> _showMapTypePicker() async {
    final selected = await showModalBottomSheet<MapType>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Map Type',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                _NavigationMapTypeTile(
                  icon: Icons.satellite_alt_rounded,
                  title: 'Satellite',
                  isSelected: _mapType == MapType.satellite,
                  onTap: () => Navigator.pop(context, MapType.satellite),
                ),
                _NavigationMapTypeTile(
                  icon: Icons.map_outlined,
                  title: 'Default',
                  isSelected: _mapType == MapType.normal,
                  onTap: () => Navigator.pop(context, MapType.normal),
                ),
                _NavigationMapTypeTile(
                  icon: Icons.terrain_rounded,
                  title: 'Terrain',
                  isSelected: _mapType == MapType.terrain,
                  onTap: () => Navigator.pop(context, MapType.terrain),
                ),
                _NavigationMapTypeTile(
                  icon: Icons.layers_rounded,
                  title: 'Hybrid',
                  isSelected: _mapType == MapType.hybrid,
                  onTap: () => Navigator.pop(context, MapType.hybrid),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || selected == _mapType || !mounted) return;

    setState(() => _mapType = selected);
    await _controller?.setMapType(mapType: selected);
  }

  Future<void> _onRoadSnappedLocation(
    RoadSnappedLocationUpdatedEvent event,
  ) async {
    final now = DateTime.now();
    if (_lastLocationWrite != null &&
        now.difference(_lastLocationWrite!) < const Duration(seconds: 5)) {
      return;
    }

    _lastLocationWrite = now;
    await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .update({
          'driverLat': event.location.latitude,
          'driverLng': event.location.longitude,
          'lastLocationUpdate': Timestamp.now(),
        });
  }

  Future<void> _handleArrival(OnArrivalEvent event) async {
    if (widget.includePickupStop && !_pickupReached) {
      _pickupReached = true;
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
            'pickupReachedAt': Timestamp.now(),
            'notificationStatus': 'pickupReached',
          });
      final response = await GoogleMapsNavigator.continueToNextDestination();
      if (!mounted) return;
      setState(() {
        _message = response.waypoint == null
            ? 'Pickup reached'
            : 'Pickup reached. Continuing to drop-off';
      });
      return;
    }

    await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .update({
          'arrivedAtDropoff': Timestamp.now(),
          'notificationStatus': 'driverArrived',
        });
    if (!mounted) return;
    setState(() => _message = 'You have arrived at the drop-off');
  }

  Future<void> _stopNavigation() async {
    if (_stoppingNavigation) return;

    setState(() {
      _stoppingNavigation = true;
      _stopRequested = true;
      _message = 'Stopping voice navigation';
    });

    final controller = _controller;
    if (controller != null) {
      await controller
          .setNavigationUIEnabled(false)
          .timeout(const Duration(seconds: 2), onTimeout: () {})
          .catchError((_) {});
    }
    await VoiceNavigationControlService.stopActiveGuidance().timeout(
      const Duration(seconds: 12),
      onTimeout: () => false,
    );
    await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .set({
          'voiceNavigationStatus': 'stopped',
          'voiceNavigationStoppedAt': Timestamp.now(),
        }, SetOptions(merge: true))
        .timeout(const Duration(seconds: 5), onTimeout: () {})
        .catchError((_) {});
    _guidanceRunning = false;
    _sessionReady = false;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _keepRunningInBackground() async {
    _keepRunningAfterClose = true;
    await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .set({
          'voiceNavigationStatus': 'background',
          'voiceNavigationBackgroundAt': Timestamp.now(),
        }, SetOptions(merge: true));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _handleCloseRequest() async {
    if (!_guidanceRunning) {
      await _stopNavigation();
      return;
    }

    final action = await showModalBottomSheet<_NavigationExitAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => const _NavigationExitSheet(),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _NavigationExitAction.keepRunning:
        await _keepRunningInBackground();
      case _NavigationExitAction.stop:
        await _stopNavigation();
    }
  }

  Future<void> _clearListeners() async {
    await _locationSubscription?.cancel();
    await _reroutingSubscription?.cancel();
    await _arrivalSubscription?.cancel();
    await _etaSubscription?.cancel();
    _locationSubscription = null;
    _reroutingSubscription = null;
    _arrivalSubscription = null;
    _etaSubscription = null;
  }

  void _setFailure(String message) {
    if (!mounted || _disposed) return;
    if (_guidanceRunning) {
      setState(() => _message = message);
      return;
    }

    setState(() {
      _routeFailed = true;
      _voicePanelExpanded = true;
      _message = message;
    });
  }

  String _locationAccessMessage(LocationAccessStatus status) {
    switch (status) {
      case LocationAccessStatus.serviceDisabled:
        return 'Turn on location service to start voice navigation.';
      case LocationAccessStatus.deniedForever:
        return 'Allow location from phone settings to use voice navigation.';
      case LocationAccessStatus.denied:
        return 'Location permission is required for voice navigation.';
      case LocationAccessStatus.unavailable:
        return 'Location is not available on this device.';
      case LocationAccessStatus.granted:
        return 'Location is ready.';
    }
  }

  String _sessionErrorMessage(SessionInitializationError code) {
    switch (code) {
      case SessionInitializationError.notAuthorized:
        return 'The Google Navigation SDK is not authorized for this app key.';
      case SessionInitializationError.locationPermissionMissing:
        return 'Location permission is required for voice navigation.';
      case SessionInitializationError.termsNotAccepted:
        return 'Accept Google navigation terms to use voice guidance.';
    }
  }

  String _routeStatusMessage(NavigationRouteStatus status) {
    switch (status) {
      case NavigationRouteStatus.apiKeyNotAuthorized:
        return 'The Google map key is not allowed to use Navigation SDK yet.';
      case NavigationRouteStatus.routeNotFound:
        return 'Google could not find a drivable route for this delivery.';
      case NavigationRouteStatus.networkError:
        return 'Network problem. Please reconnect and try again.';
      case NavigationRouteStatus.quotaExceeded:
      case NavigationRouteStatus.quotaCheckFailed:
        return 'Navigation quota is not available for this Google project.';
      case NavigationRouteStatus.locationUnavailable:
      case NavigationRouteStatus.locationUnknown:
        return 'Waiting for a stronger GPS signal. Try again in a clearer area.';
      case NavigationRouteStatus.duplicateWaypointsError:
      case NavigationRouteStatus.noWaypointsError:
      case NavigationRouteStatus.waypointError:
        return 'This job location needs to be checked before navigation can start.';
      case NavigationRouteStatus.travelModeUnsupported:
        return 'Driving navigation is not supported for this route.';
      case NavigationRouteStatus.internalError:
      case NavigationRouteStatus.statusCanceled:
      case NavigationRouteStatus.unknown:
      case NavigationRouteStatus.statusOk:
        return 'Voice navigation could not start. Please try again.';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_clearListeners());
    if (_sessionReady && !_stopRequested) {
      if (_keepRunningAfterClose) {
        unawaited(VoiceNavigationControlService.detachListenersOnly());
      } else {
        unawaited(VoiceNavigationControlService.stopActiveGuidance());
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleCloseRequest());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),
        body: Stack(
          children: [
            Positioned.fill(
              child: _sessionReady
                  ? GoogleMapsNavigationView(
                      onViewCreated: _onViewCreated,
                      initialNavigationUIEnabledPreference:
                          NavigationUIEnabledPreference.automatic,
                      initialForceNightMode: NavigationForceNightMode.auto,
                      initialMapType: _mapType,
                      initialZoomControlsEnabled: true,
                      initialCompassEnabled: true,
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          latitude: widget.pickupLat,
                          longitude: widget.pickupLng,
                        ),
                        zoom: 15,
                      ),
                      onPromptVisibilityChanged: (visible) {
                        if (mounted) {
                          setState(() => _promptVisible = visible);
                        }
                      },
                    )
                  : _VoiceNavigationSetupView(
                      pickupLabel: widget.pickupLabel,
                      dropoffLabel: widget.dropoffLabel,
                      reviewingGoogleNotice: _reviewingGoogleNotice,
                    ),
            ),
            if (_sessionReady) ...[
              Positioned(
                top: topPadding + 10,
                left: 14,
                child: _RoundMapButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Close navigation',
                  onPressed: _handleCloseRequest,
                ),
              ),
              Positioned(
                top: topPadding + 10,
                right: 14,
                child: _RoundMapButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'My location',
                  onPressed: () => _controller?.followMyLocation(
                    CameraPerspective.tilted,
                    zoomLevel: 17,
                  ),
                ),
              ),
              Positioned(
                top: topPadding + 62,
                right: 14,
                child: _RoundMapButton(
                  icon: Icons.layers_rounded,
                  tooltip: 'Change map type',
                  onPressed: _showMapTypePicker,
                ),
              ),
            ],
            if (!_promptVisible && _sessionReady)
              Positioned(
                left: 16,
                right: 16,
                bottom: 18 + MediaQuery.of(context).padding.bottom,
                child: _VoiceNavigationPanel(
                  message: _message,
                  pickupLabel: widget.pickupLabel,
                  dropoffLabel: widget.dropoffLabel,
                  routeFailed: _routeFailed,
                  guidanceRunning: _guidanceRunning,
                  remainingDistanceMeters: _remainingDistanceMeters,
                  remainingTimeSeconds: _remainingTimeSeconds,
                  onRetry: _routeFailed ? _startGuidanceWithRetry : null,
                  onKeepRunning: _guidanceRunning
                      ? _keepRunningInBackground
                      : null,
                  onStop: _stopNavigation,
                  isStopping: _stoppingNavigation,
                  expanded: _voicePanelExpanded || _routeFailed,
                  onToggleExpanded: () {
                    setState(() {
                      _voicePanelExpanded = !_voicePanelExpanded;
                    });
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _NavigationExitAction { keepRunning, stop }

class _VoiceNavigationSetupView extends StatelessWidget {
  const _VoiceNavigationSetupView({
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.reviewingGoogleNotice,
  });

  final String pickupLabel;
  final String dropoffLabel;
  final bool reviewingGoogleNotice;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF6F8FC),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFFDF6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.navigation_rounded,
                  color: Color(0xFF0F766E),
                  size: 30,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Voice Navigation',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                reviewingGoogleNotice
                    ? 'Please accept the required Google notice to start turn-by-turn guidance.'
                    : 'Preparing the route and voice guidance for this delivery.',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x140F172A),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: _TinyRouteLine(
                  pickupLabel: pickupLabel,
                  dropoffLabel: dropoffLabel,
                ),
              ),
              const SizedBox(height: 18),
              const _SetupStep(
                icon: Icons.gps_fixed_rounded,
                title: 'Live GPS route',
                body: 'The map follows the driver position during delivery.',
              ),
              const SizedBox(height: 12),
              const _SetupStep(
                icon: Icons.alt_route_rounded,
                title: 'Automatic rerouting',
                body:
                    'Google Navigation recalculates when the driver changes road.',
              ),
              const SizedBox(height: 12),
              const _SetupStep(
                icon: Icons.volume_up_rounded,
                title: 'Voice instructions',
                body:
                    'Directions will continue until the driver stops guidance.',
              ),
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      reviewingGoogleNotice
                          ? 'Waiting for acceptance'
                          : 'Preparing navigation',
                      style: const TextStyle(
                        color: Color(0xFF0F766E),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFEFFDF6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF0F766E), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavigationExitSheet extends StatelessWidget {
  const _NavigationExitSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Voice Navigation',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Do you want EFATA to keep giving directions in the background?',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pop(context, _NavigationExitAction.keepRunning),
              icon: const Icon(Icons.volume_up_rounded),
              label: const Text('Keep Running'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pop(context, _NavigationExitAction.stop),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop Navigation'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundMapButton extends StatelessWidget {
  const _RoundMapButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: const Color(0xFF0F172A)),
        onPressed: onPressed,
      ),
    );
  }
}

class _NavigationMapTypeTile extends StatelessWidget {
  const _NavigationMapTypeTile({
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? const Color(0xFF0F766E)
        : const Color(0xFF334155);

    return Material(
      color: isSelected ? const Color(0xFFEFFDF6) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF16A34A),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceNavigationPanel extends StatelessWidget {
  const _VoiceNavigationPanel({
    required this.message,
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.routeFailed,
    required this.guidanceRunning,
    required this.remainingDistanceMeters,
    required this.remainingTimeSeconds,
    required this.onRetry,
    required this.onKeepRunning,
    required this.onStop,
    required this.isStopping,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final String message;
  final String pickupLabel;
  final String dropoffLabel;
  final bool routeFailed;
  final bool guidanceRunning;
  final double? remainingDistanceMeters;
  final double? remainingTimeSeconds;
  final VoidCallback? onRetry;
  final VoidCallback? onKeepRunning;
  final VoidCallback onStop;
  final bool isStopping;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    if (guidanceRunning && !routeFailed && !expanded) {
      return _CompactVoiceNavigationBar(
        message: message,
        distanceLabel: remainingDistanceMeters == null
            ? null
            : _formatDistance(remainingDistanceMeters!),
        durationLabel: remainingTimeSeconds == null
            ? null
            : _formatDuration(remainingTimeSeconds!),
        onMore: onToggleExpanded,
        onStop: onStop,
        isStopping: isStopping,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330F172A),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: routeFailed
                        ? const Color(0xFFFFEBEE)
                        : const Color(0xFFEFFDF6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    routeFailed
                        ? Icons.warning_amber_rounded
                        : Icons.volume_up_rounded,
                    color: routeFailed
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guidanceRunning ? 'Voice Navigation' : 'Navigation',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (guidanceRunning && !routeFailed)
                  IconButton(
                    tooltip: 'Hide details',
                    onPressed: onToggleExpanded,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
              ],
            ),
            if (remainingDistanceMeters != null ||
                remainingTimeSeconds != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  if (remainingDistanceMeters != null)
                    _MetricPill(
                      icon: Icons.route_rounded,
                      value: _formatDistance(remainingDistanceMeters!),
                    ),
                  if (remainingTimeSeconds != null) ...[
                    const SizedBox(width: 8),
                    _MetricPill(
                      icon: Icons.schedule_rounded,
                      value: _formatDuration(remainingTimeSeconds!),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 14),
            _TinyRouteLine(
              pickupLabel: pickupLabel,
              dropoffLabel: dropoffLabel,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (onRetry != null) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try Again'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (onKeepRunning != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isStopping ? null : onKeepRunning,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Keep Running'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isStopping ? null : onStop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      isStopping
                          ? Icons.hourglass_top_rounded
                          : Platform.isAndroid
                          ? Icons.stop_circle_outlined
                          : Icons.close_rounded,
                    ),
                    label: Text(isStopping ? 'Stopping...' : 'Stop'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainder = minutes % 60;
      return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
    }
    return '$minutes min';
  }
}

class _CompactVoiceNavigationBar extends StatelessWidget {
  const _CompactVoiceNavigationBar({
    required this.message,
    required this.distanceLabel,
    required this.durationLabel,
    required this.onMore,
    required this.onStop,
    required this.isStopping,
  });

  final String message;
  final String? distanceLabel;
  final String? durationLabel;
  final VoidCallback onMore;
  final VoidCallback onStop;
  final bool isStopping;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: const Color(0x330F172A),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEFFDF6),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.volume_up_rounded,
                color: Color(0xFF0F766E),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onMore,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Voice Navigation',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _compactStatus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'More details',
              onPressed: onMore,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Stop navigation',
              onPressed: isStopping ? null : onStop,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE5E7EB),
                disabledForegroundColor: const Color(0xFF94A3B8),
              ),
              icon: Icon(
                isStopping
                    ? Icons.hourglass_top_rounded
                    : Platform.isAndroid
                    ? Icons.stop_circle_outlined
                    : Icons.close_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _compactStatus {
    final metrics = [
      if (distanceLabel != null) distanceLabel!,
      if (durationLabel != null) durationLabel!,
    ].join(' - ');

    if (metrics.isEmpty) return message;
    return metrics;
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF475569)),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyRouteLine extends StatelessWidget {
  const _TinyRouteLine({required this.pickupLabel, required this.dropoffLabel});

  final String pickupLabel;
  final String dropoffLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RouteStop(
          icon: Icons.radio_button_checked_rounded,
          label: pickupLabel,
        ),
        const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 16,
              child: VerticalDivider(
                color: Color(0xFF94A3B8),
                thickness: 2,
                width: 14,
              ),
            ),
          ),
        ),
        _RouteStop(icon: Icons.location_on_rounded, label: dropoffLabel),
      ],
    );
  }
}

class _RouteStop extends StatelessWidget {
  const _RouteStop({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0F766E), size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
