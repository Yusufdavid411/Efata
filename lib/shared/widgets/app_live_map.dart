import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/services/google_route_service.dart';
import '../../core/services/location_service.dart';

class AppLiveMap extends StatefulWidget {
  const AppLiveMap({
    super.key,
    required this.pickupPoint,
    required this.dropoffPoint,
    required this.driverPoint,
    this.followDriver = false,
    this.activeTargetPoint,
    this.activeTargetLabel,
    this.showRouteStatus = true,
  });

  final LatLng pickupPoint;
  final LatLng dropoffPoint;
  final LatLng? driverPoint;
  final bool followDriver;
  final LatLng? activeTargetPoint;
  final String? activeTargetLabel;
  final bool showRouteStatus;

  @override
  State<AppLiveMap> createState() => _AppLiveMapState();
}

class _AppLiveMapState extends State<AppLiveMap> {
  final Completer<GoogleMapController> _mapController = Completer();

  GoogleRouteResult? route;
  GoogleRouteResult? activeRoute;
  LatLng? userPoint;
  String? routeError;
  String? activeRouteError;
  String? routeKey;
  String? activeRouteKey;
  LatLng? lastFollowedDriverPoint;
  LatLng? lastActiveRouteOrigin;
  LatLng? lastActiveRouteTarget;
  DateTime? lastActiveRouteAt;
  Timer? rerouteDebounce;
  bool loadingRoute = false;
  bool loadingActiveRoute = false;
  bool locationChecked = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _loadRouteIfNeeded();
    _loadActiveRouteIfNeeded(force: true);
  }

  @override
  void didUpdateWidget(covariant AppLiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.pickupPoint != widget.pickupPoint ||
        oldWidget.dropoffPoint != widget.dropoffPoint ||
        oldWidget.activeTargetPoint != widget.activeTargetPoint) {
      _loadRouteIfNeeded();
      _loadActiveRouteIfNeeded(force: true);
      _fitRouteAfterFrame();
    }

    if (oldWidget.driverPoint != widget.driverPoint ||
        oldWidget.followDriver != widget.followDriver) {
      _scheduleActiveReroute();
      if (widget.followDriver) {
        _followDriverAfterFrame();
        return;
      }
      _fitRouteAfterFrame();
    }
  }

  @override
  void dispose() {
    rerouteDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    final position = await LocationService.getCurrentPosition();
    if (!mounted) return;

    setState(() {
      locationChecked = true;
      if (position != null) {
        userPoint = LatLng(position.latitude, position.longitude);
      }
    });
    _loadActiveRouteIfNeeded(force: true);
  }

  Future<void> _loadRouteIfNeeded() async {
    final nextKey = _routeKey(widget.pickupPoint, widget.dropoffPoint);
    if (nextKey == routeKey) return;

    routeKey = nextKey;
    setState(() {
      loadingRoute = true;
      routeError = null;
    });

    try {
      final result = await GoogleRouteService.routeBetween(
        pickup: widget.pickupPoint,
        dropoff: widget.dropoffPoint,
      );

      if (!mounted || routeKey != nextKey) return;

      setState(() {
        route = result;
        routeError = result == null
            ? 'Road route unavailable. Showing direct line.'
            : null;
      });
    } catch (_) {
      if (!mounted || routeKey != nextKey) return;

      setState(() {
        route = null;
        routeError = 'Road route unavailable. Showing direct line.';
      });
    } finally {
      if (mounted && routeKey == nextKey) {
        setState(() => loadingRoute = false);
      }
    }
  }

  void _scheduleActiveReroute() {
    final origin = widget.driverPoint ?? userPoint;
    final target = widget.activeTargetPoint;

    if (origin == null || target == null) return;

    final targetChanged =
        lastActiveRouteTarget == null ||
        _distanceBetween(lastActiveRouteTarget!, target) > 30;
    final movedFarEnough =
        lastActiveRouteOrigin == null ||
        _distanceBetween(lastActiveRouteOrigin!, origin) >= 90;
    final waitedLongEnough =
        lastActiveRouteAt == null ||
        DateTime.now().difference(lastActiveRouteAt!) >
            const Duration(seconds: 25);

    if (!targetChanged && (!movedFarEnough || !waitedLongEnough)) return;

    rerouteDebounce?.cancel();
    rerouteDebounce = Timer(const Duration(milliseconds: 900), () {
      _loadActiveRouteIfNeeded(force: targetChanged);
    });
  }

  Future<void> _loadActiveRouteIfNeeded({bool force = false}) async {
    final origin = widget.driverPoint ?? userPoint;
    final target = widget.activeTargetPoint;

    if (origin == null || target == null) {
      if (!mounted) return;
      setState(() {
        activeRoute = null;
        activeRouteError = null;
        activeRouteKey = null;
      });
      return;
    }

    final nextKey = _routeKey(origin, target, precision: 4);
    if (!force && nextKey == activeRouteKey) return;

    activeRouteKey = nextKey;
    lastActiveRouteOrigin = origin;
    lastActiveRouteTarget = target;
    lastActiveRouteAt = DateTime.now();

    setState(() {
      loadingActiveRoute = true;
      activeRouteError = null;
    });

    try {
      final result = await GoogleRouteService.routeBetween(
        pickup: origin,
        dropoff: target,
        cachePrecision: 4,
      );

      if (!mounted || activeRouteKey != nextKey) return;

      setState(() {
        activeRoute = result;
        activeRouteError = result == null
            ? 'Road route unavailable. Showing direct line.'
            : null;
      });
    } catch (_) {
      if (!mounted || activeRouteKey != nextKey) return;

      setState(() {
        activeRoute = null;
        activeRouteError = 'Road route unavailable. Showing direct line.';
      });
    } finally {
      if (mounted && activeRouteKey == nextKey) {
        setState(() => loadingActiveRoute = false);
      }
    }
  }

  String _routeKey(LatLng pickup, LatLng dropoff, {int precision = 6}) {
    return [
      pickup.latitude.toStringAsFixed(precision),
      pickup.longitude.toStringAsFixed(precision),
      dropoff.latitude.toStringAsFixed(precision),
      dropoff.longitude.toStringAsFixed(precision),
    ].join(',');
  }

  double _distanceBetween(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  void _fitRouteAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
  }

  Future<void> _fitRoute() async {
    if (!_mapController.isCompleted) return;

    final controller = await _mapController.future;
    final points = [
      widget.pickupPoint,
      widget.dropoffPoint,
      if (widget.driverPoint != null) widget.driverPoint!,
      if (userPoint != null) userPoint!,
    ];

    final activePoints = activeRoute?.points ?? route?.points;
    if (activePoints != null && activePoints.isNotEmpty) {
      points.addAll(activePoints);
    }

    final bounds = _boundsFor(points);
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
  }

  void _followDriverAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _followDriver());
  }

  Future<void> _followDriver() async {
    if (!_mapController.isCompleted) return;

    final target = widget.driverPoint ?? userPoint ?? widget.pickupPoint;
    if (lastFollowedDriverPoint == target) return;

    lastFollowedDriverPoint = target;
    final controller = await _mapController.future;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 16, tilt: 45),
      ),
    );
  }

  LatLngBounds _boundsFor(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }

    if (minLat == maxLat) {
      minLat -= 0.002;
      maxLat += 0.002;
    }

    if (minLng == maxLng) {
      minLng -= 0.002;
      maxLng += 0.002;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = route?.points.isNotEmpty == true
        ? route!.points
        : [widget.pickupPoint, widget.dropoffPoint];
    final activeRoutePoints = activeRoute?.points.isNotEmpty == true
        ? activeRoute!.points
        : null;
    final driverRouteStart = widget.driverPoint ?? userPoint;
    final activeTargetPoint = widget.activeTargetPoint;
    final markers = {
      Marker(
        markerId: const MarkerId('pickup'),
        position: widget.pickupPoint,
        infoWindow: const InfoWindow(title: 'Pickup'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('dropoff'),
        position: widget.dropoffPoint,
        infoWindow: const InfoWindow(title: 'Drop-off'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      if (widget.driverPoint != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: widget.driverPoint!,
          infoWindow: const InfoWindow(title: 'Driver'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      if (userPoint != null)
        Marker(
          markerId: const MarkerId('current-location'),
          position: userPoint!,
          infoWindow: const InfoWindow(title: 'Your location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueViolet,
          ),
        ),
    };

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: widget.driverPoint ?? widget.pickupPoint,
            zoom: 13,
          ),
          markers: markers,
          polylines: {
            Polyline(
              polylineId: const PolylineId('delivery-route'),
              points: routePoints,
              width: activeRoutePoints == null ? 6 : 4,
              color: route == null
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF0F766E),
            ),
            if (activeRoutePoints != null)
              Polyline(
                polylineId: const PolylineId('driver-active-road-route'),
                points: activeRoutePoints,
                width: 7,
                color: const Color(0xFF2563EB),
              ),
            if (activeRoutePoints == null &&
                driverRouteStart != null &&
                activeTargetPoint != null)
              Polyline(
                polylineId: const PolylineId('driver-active-leg'),
                points: [driverRouteStart, activeTargetPoint],
                width: 5,
                color: const Color(0xFF2563EB),
                patterns: [PatternItem.dash(18), PatternItem.gap(10)],
              ),
          },
          myLocationButtonEnabled: true,
          myLocationEnabled: userPoint != null,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: true,
          rotateGesturesEnabled: true,
          scrollGesturesEnabled: true,
          tiltGesturesEnabled: true,
          zoomGesturesEnabled: true,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
          onMapCreated: (controller) {
            if (!_mapController.isCompleted) {
              _mapController.complete(controller);
            }
            if (widget.followDriver) {
              _followDriverAfterFrame();
            } else {
              _fitRouteAfterFrame();
            }
          },
        ),
        Positioned(
          left: 12,
          top: 12,
          child: _MapControlButton(
            icon: Icons.center_focus_strong_rounded,
            tooltip: 'Fit route',
            onTap: _fitRoute,
          ),
        ),
        Positioned(
          left: 12,
          top: 62,
          child: _MapControlButton(
            icon: Icons.my_location_rounded,
            tooltip: 'Follow driver',
            isActive: widget.followDriver,
            onTap: _followDriver,
          ),
        ),
        if (widget.showRouteStatus)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _RouteStatusCard(
              route: route,
              activeRoute: activeRoute,
              routeError: activeRouteError ?? routeError,
              loadingRoute: loadingRoute || loadingActiveRoute,
              locationChecked: locationChecked,
              activeTargetLabel: widget.activeTargetLabel,
              isFollowing: widget.followDriver,
            ),
          ),
      ],
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF0F766E) : const Color(0xFF0F172A);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: color),
          ),
        ),
      ),
    );
  }
}

class _RouteStatusCard extends StatelessWidget {
  const _RouteStatusCard({
    required this.route,
    required this.activeRoute,
    required this.routeError,
    required this.loadingRoute,
    required this.locationChecked,
    required this.activeTargetLabel,
    required this.isFollowing,
  });

  final GoogleRouteResult? route;
  final GoogleRouteResult? activeRoute;
  final String? routeError;
  final bool loadingRoute;
  final bool locationChecked;
  final String? activeTargetLabel;
  final bool isFollowing;

  @override
  Widget build(BuildContext context) {
    final displayRoute = activeRoute ?? route;
    final routeMessage = displayRoute != null
        ? '${displayRoute.distanceKm.toStringAsFixed(1)} km, about ${displayRoute.durationMinutes} min'
        : routeError ?? 'Delivery route';
    final message = activeTargetLabel == null
        ? routeMessage
        : '$activeTargetLabel, $routeMessage';

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (loadingRoute)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else
              Icon(
                isFollowing
                    ? Icons.navigation_rounded
                    : displayRoute == null
                    ? Icons.route_outlined
                    : Icons.check_circle_outline_rounded,
                color: isFollowing || displayRoute != null
                    ? const Color(0xFF0F766E)
                    : const Color(0xFF64748B),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!locationChecked)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text(
                  'GPS...',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
