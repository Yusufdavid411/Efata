import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
  LatLng? userPoint;
  String? routeError;
  String? routeKey;
  LatLng? lastFollowedDriverPoint;
  bool loadingRoute = false;
  bool locationChecked = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _loadRouteIfNeeded();
  }

  @override
  void didUpdateWidget(covariant AppLiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.pickupPoint != widget.pickupPoint ||
        oldWidget.dropoffPoint != widget.dropoffPoint) {
      _loadRouteIfNeeded();
      _fitRouteAfterFrame();
    }

    if (oldWidget.driverPoint != widget.driverPoint ||
        oldWidget.followDriver != widget.followDriver) {
      if (widget.followDriver) {
        _followDriverAfterFrame();
        return;
      }
      _fitRouteAfterFrame();
    }
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
            ? 'Route details unavailable. Showing direct delivery line.'
            : null;
      });
    } catch (_) {
      if (!mounted || routeKey != nextKey) return;

      setState(() {
        route = null;
        routeError = 'Route details unavailable. Showing direct delivery line.';
      });
    } finally {
      if (mounted && routeKey == nextKey) {
        setState(() => loadingRoute = false);
      }
    }
  }

  String _routeKey(LatLng pickup, LatLng dropoff) {
    return [
      pickup.latitude.toStringAsFixed(6),
      pickup.longitude.toStringAsFixed(6),
      dropoff.latitude.toStringAsFixed(6),
      dropoff.longitude.toStringAsFixed(6),
    ].join(',');
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

    if (points.isEmpty) return;

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
              width: 6,
              color: route == null
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF0F766E),
            ),
            if (driverRouteStart != null && activeTargetPoint != null)
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
              routeError: routeError,
              loadingRoute: loadingRoute,
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
    required this.routeError,
    required this.loadingRoute,
    required this.locationChecked,
    required this.activeTargetLabel,
    required this.isFollowing,
  });

  final GoogleRouteResult? route;
  final String? routeError;
  final bool loadingRoute;
  final bool locationChecked;
  final String? activeTargetLabel;
  final bool isFollowing;

  @override
  Widget build(BuildContext context) {
    final routeMessage = route != null
        ? '${route!.distanceKm.toStringAsFixed(1)} km • about ${route!.durationMinutes} min'
        : routeError ?? 'Delivery route';
    final message = activeTargetLabel == null
        ? routeMessage
        : '$activeTargetLabel, $routeMessage';
    final displayMessage = message.replaceAll(RegExp(r'[^\x00-\x7F]+'), ',');

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
                    : route == null
                    ? Icons.route_outlined
                    : Icons.check_circle_outline_rounded,
                color: isFollowing || route != null
                    ? const Color(0xFF0F766E)
                    : const Color(0xFF64748B),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayMessage,
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
