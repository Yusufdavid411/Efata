import 'dart:async';

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
  });

  final LatLng pickupPoint;
  final LatLng dropoffPoint;
  final LatLng? driverPoint;

  @override
  State<AppLiveMap> createState() => _AppLiveMapState();
}

class _AppLiveMapState extends State<AppLiveMap> {
  final Completer<GoogleMapController> _mapController = Completer();

  GoogleRouteResult? route;
  LatLng? userPoint;
  String? routeError;
  String? routeKey;
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

    if (oldWidget.driverPoint != widget.driverPoint) {
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
              width: 5,
              color: route == null
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF0F766E),
            ),
          },
          myLocationButtonEnabled: true,
          myLocationEnabled: userPoint != null,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (controller) {
            if (!_mapController.isCompleted) {
              _mapController.complete(controller);
            }
            _fitRouteAfterFrame();
          },
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _RouteStatusCard(
            route: route,
            routeError: routeError,
            loadingRoute: loadingRoute,
            locationChecked: locationChecked,
          ),
        ),
      ],
    );
  }
}

class _RouteStatusCard extends StatelessWidget {
  const _RouteStatusCard({
    required this.route,
    required this.routeError,
    required this.loadingRoute,
    required this.locationChecked,
  });

  final GoogleRouteResult? route;
  final String? routeError;
  final bool loadingRoute;
  final bool locationChecked;

  @override
  Widget build(BuildContext context) {
    final message = route != null
        ? '${route!.distanceKm.toStringAsFixed(1)} km • about ${route!.durationMinutes} min'
        : routeError ?? 'Delivery route';

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
                route == null
                    ? Icons.route_outlined
                    : Icons.check_circle_outline_rounded,
                color: route == null
                    ? const Color(0xFF64748B)
                    : const Color(0xFF0F766E),
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
