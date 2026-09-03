import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/services/app_notification_banner_service.dart';
import '../../core/services/location_service.dart';

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final Completer<GoogleMapController> mapController = Completer();
  final TextEditingController labelController = TextEditingController();

  LatLng selectedLocation = const LatLng(6.5244, 3.3792);
  String selectedAddress = 'Selected location in Lagos';
  String? locationMessage;
  bool locating = false;
  bool locationGranted = false;

  @override
  void initState() {
    super.initState();
    moveToCurrentLocation(showErrors: false);
  }

  Future<void> moveToCurrentLocation({bool showErrors = true}) async {
    setState(() {
      locating = true;
      locationMessage = null;
    });

    final access = await LocationService.requestLocationAccess();

    if (access != LocationAccessStatus.granted) {
      if (!mounted) return;

      final message = _permissionMessage(access);
      setState(() {
        locating = false;
        locationMessage = showErrors ? message : null;
      });

      if (showErrors) {
        AppNotificationBannerService.error(message, title: 'Location needed');
      }
      return;
    }

    if (mounted) setState(() => locationGranted = true);

    try {
      final position = await LocationService.getCurrentPosition();
      if (position == null) throw Exception('Location unavailable');

      final point = LatLng(position.latitude, position.longitude);
      selectLocation(point, address: 'Current location', animate: true);

      if (!mounted) return;
      setState(() {
        locating = false;
        locationMessage = null;
      });
    } catch (_) {
      if (!mounted) return;

      const message = 'Current location is unavailable right now.';
      setState(() {
        locating = false;
        locationMessage = showErrors ? message : null;
      });

      if (showErrors) {
        AppNotificationBannerService.error(message, title: 'Location issue');
      }
    }
  }

  String _permissionMessage(LocationAccessStatus status) {
    switch (status) {
      case LocationAccessStatus.serviceDisabled:
        return 'Turn on location services to use your current position.';
      case LocationAccessStatus.denied:
        return 'Location permission was denied.';
      case LocationAccessStatus.deniedForever:
        return 'Location permission is permanently denied. Enable it in app settings.';
      case LocationAccessStatus.unavailable:
        return 'Location is unavailable on this device.';
      case LocationAccessStatus.granted:
        return 'Location access granted.';
    }
  }

  Future<void> selectLocation(
    LatLng point, {
    String? address,
    bool animate = false,
  }) async {
    final nextAddress =
        address ??
        'Selected location (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})';

    setState(() {
      selectedLocation = point;
      selectedAddress = nextAddress;
      labelController.text = nextAddress;
    });

    if (animate && mapController.isCompleted) {
      final controller = await mapController.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: point, zoom: 16)),
      );
    }
  }

  @override
  void dispose() {
    labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Pick location'),
        backgroundColor: Colors.white.withValues(alpha: 0.92),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: selectedLocation,
              zoom: 13,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('selected-location'),
                position: selectedLocation,
                infoWindow: const InfoWindow(title: 'Selected location'),
              ),
            },
            myLocationEnabled: locationGranted,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            onTap: (point) => selectLocation(point, animate: false),
            onMapCreated: (controller) {
              if (!mapController.isCompleted) {
                mapController.complete(controller);
              }
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.of(context).padding.top + 70,
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: labelController,
                        decoration: const InputDecoration(
                          labelText: 'Location label',
                          hintText: 'Example: Warehouse gate or Site entrance',
                          prefixIcon: Icon(Icons.edit_location_alt_outlined),
                        ),
                        onChanged: (value) {
                          selectedAddress = value.trim().isEmpty
                              ? 'Selected location (${selectedLocation.latitude.toStringAsFixed(5)}, ${selectedLocation.longitude.toStringAsFixed(5)})'
                              : value.trim();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Use current location',
                      onPressed: locating
                          ? null
                          : () => moveToCurrentLocation(showErrors: true),
                      icon: locating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: SafeArea(
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected location',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        selectedAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (locationMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          locationMessage!,
                          style: const TextStyle(color: Color(0xFFDC2626)),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context, {
                            'address': selectedAddress,
                            'latitude': selectedLocation.latitude,
                            'longitude': selectedLocation.longitude,
                          });
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Use This Location'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
