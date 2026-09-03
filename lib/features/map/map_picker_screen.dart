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
  MapType mapType = MapType.satellite;

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

  Future<void> showMapTypePicker() async {
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
                _MapTypeTile(
                  icon: Icons.satellite_alt_rounded,
                  title: 'Satellite',
                  subtitle: 'Best for finding your exact pickup point.',
                  isSelected: mapType == MapType.satellite,
                  onTap: () => Navigator.pop(context, MapType.satellite),
                ),
                _MapTypeTile(
                  icon: Icons.map_outlined,
                  title: 'Default',
                  subtitle: 'Clean road map view.',
                  isSelected: mapType == MapType.normal,
                  onTap: () => Navigator.pop(context, MapType.normal),
                ),
                _MapTypeTile(
                  icon: Icons.terrain_rounded,
                  title: 'Terrain',
                  subtitle: 'Shows land shape and routes.',
                  isSelected: mapType == MapType.terrain,
                  onTap: () => Navigator.pop(context, MapType.terrain),
                ),
                _MapTypeTile(
                  icon: Icons.layers_rounded,
                  title: 'Hybrid',
                  subtitle: 'Satellite view with road names.',
                  isSelected: mapType == MapType.hybrid,
                  onTap: () => Navigator.pop(context, MapType.hybrid),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || selected == mapType || !mounted) return;

    setState(() => mapType = selected);
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
            mapType: mapType,
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
            right: 16,
            top: MediaQuery.of(context).padding.top + 154,
            child: _MapPickerButton(
              icon: Icons.layers_rounded,
              label: 'View',
              tooltip: 'Change map type',
              isActive: mapType != MapType.normal,
              onTap: showMapTypePicker,
            ),
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

class _MapPickerButton extends StatelessWidget {
  const _MapPickerButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
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
        elevation: 3,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 54,
            height: 50,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 21),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapTypeTile extends StatelessWidget {
  const _MapTypeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
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
