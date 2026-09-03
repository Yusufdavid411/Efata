import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:logistics_app/core/services/location_service.dart';

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
  String _message = 'Preparing voice navigation';
  double? _remainingDistanceMeters;
  double? _remainingTimeSeconds;
  DateTime? _lastLocationWrite;

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
      final accepted =
          await GoogleMapsNavigator.areTermsAccepted() ||
          await GoogleMapsNavigator.showTermsAndConditionsDialog(
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

      if (!accepted) {
        _setFailure('Accept Google navigation terms to use voice guidance.');
        return;
      }

      await GoogleMapsNavigator.initializeNavigationSession(
        taskRemovedBehavior: TaskRemovedBehavior.continueService,
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

      await _startGuidanceWithRetry();
    } on SessionInitializationException catch (error) {
      _setFailure(_sessionErrorMessage(error.code));
    } catch (error) {
      _setFailure(
        'Voice navigation could not start. Please check the map key.',
      );
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
    NavigationRouteStatus status = NavigationRouteStatus.locationUnavailable;

    for (var attempt = 0; attempt < 4; attempt++) {
      status = await GoogleMapsNavigator.setDestinations(_destinations);
      if (status == NavigationRouteStatus.statusOk) break;

      final shouldRetry =
          status == NavigationRouteStatus.locationUnavailable ||
          status == NavigationRouteStatus.locationUnknown;
      if (!shouldRetry) break;
      await Future.delayed(const Duration(seconds: 3));
    }

    if (status != NavigationRouteStatus.statusOk) {
      _setFailure(_routeStatusMessage(status));
      return;
    }

    await GoogleMapsNavigator.startGuidance();
    await _controller?.setNavigationUIEnabled(true);
    await _controller?.followMyLocation(
      CameraPerspective.tilted,
      zoomLevel: 17,
    );

    if (!mounted) return;
    setState(() {
      _guidanceRunning = true;
      _routeFailed = false;
      _message = widget.includePickupStop
          ? 'Voice guidance to pickup has started'
          : 'Voice guidance to drop-off has started';
    });
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
    await controller.setMyLocationEnabled(true);
    await controller.settings.setZoomControlsEnabled(true);
    await controller.settings.setCompassEnabled(true);
    await controller.setSpeedometerEnabled(true);
    await controller.setSpeedLimitIconEnabled(true);
    await controller.followMyLocation(CameraPerspective.tilted, zoomLevel: 17);
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
    try {
      if (_guidanceRunning) {
        await GoogleMapsNavigator.stopGuidance();
      }
      await GoogleMapsNavigator.cleanup();
    } on SessionNotInitializedException {
      // The session may already be cleaned up by the platform.
    }
    if (mounted) Navigator.pop(context);
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
    setState(() {
      _routeFailed = true;
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
    if (_sessionReady) {
      unawaited(GoogleMapsNavigator.cleanup(resetSession: false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
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
                : const Center(child: CircularProgressIndicator()),
          ),
          Positioned(
            top: topPadding + 10,
            left: 14,
            child: _RoundMapButton(
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            top: topPadding + 10,
            right: 14,
            child: _RoundMapButton(
              icon: Icons.my_location_rounded,
              onPressed: () => _controller?.followMyLocation(
                CameraPerspective.tilted,
                zoomLevel: 17,
              ),
            ),
          ),
          if (!_promptVisible)
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
                onStop: _stopNavigation,
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundMapButton extends StatelessWidget {
  const _RoundMapButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFF0F172A)),
        onPressed: onPressed,
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
    required this.onStop,
  });

  final String message;
  final String pickupLabel;
  final String dropoffLabel;
  final bool routeFailed;
  final bool guidanceRunning;
  final double? remainingDistanceMeters;
  final double? remainingTimeSeconds;
  final VoidCallback? onRetry;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
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
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
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
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onStop,
                    icon: Icon(
                      Platform.isAndroid
                          ? Icons.stop_circle_outlined
                          : Icons.close_rounded,
                    ),
                    label: const Text('Stop'),
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
