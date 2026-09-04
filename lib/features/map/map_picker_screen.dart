import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/services/app_notification_banner_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/place_suggestion_service.dart';

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final Completer<GoogleMapController> mapController = Completer();
  final TextEditingController searchController = TextEditingController();
  Timer? searchDebounce;

  LatLng selectedLocation = const LatLng(6.5244, 3.3792);
  String selectedAddress = '';
  String? locationMessage;
  List<PlaceSuggestion> recentSuggestions = [];
  List<PlaceSuggestion> searchSuggestions = [];
  bool locating = false;
  bool locationGranted = false;
  bool hasSelectedLocation = false;
  MapType mapType = MapType.hybrid;

  @override
  void initState() {
    super.initState();
    loadRecentPlaces();
    moveToCurrentLocation(showErrors: false);
  }

  Future<void> loadRecentPlaces() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('customerId', isEqualTo: currentUser.uid)
          .limit(40)
          .get();

      final docs = snapshot.docs.toList()
        ..sort((a, b) {
          final aTime = a.data()['createdAt'];
          final bTime = b.data()['createdAt'];
          final aMillis = aTime is Timestamp ? aTime.millisecondsSinceEpoch : 0;
          final bMillis = bTime is Timestamp ? bTime.millisecondsSinceEpoch : 0;
          return bMillis.compareTo(aMillis);
        });

      final seen = <String>{};
      final places = <PlaceSuggestion>[];

      for (final doc in docs) {
        final data = doc.data();
        _addRecentPlace(
          target: places,
          seen: seen,
          address: data['pickup'],
          latitude: data['pickupLat'],
          longitude: data['pickupLng'],
        );
        _addRecentPlace(
          target: places,
          seen: seen,
          address: data['dropoff'],
          latitude: data['dropoffLat'],
          longitude: data['dropoffLng'],
        );
      }

      if (!mounted) return;

      setState(() {
        recentSuggestions = places.take(8).toList();
      });
    } catch (_) {
      // Previous places are optional; users can still search the catalog or pin the map.
    }
  }

  void _addRecentPlace({
    required List<PlaceSuggestion> target,
    required Set<String> seen,
    required dynamic address,
    required dynamic latitude,
    required dynamic longitude,
  }) {
    final cleanAddress = address?.toString().trim() ?? '';
    final lat = latitude is num ? latitude.toDouble() : null;
    final lng = longitude is num ? longitude.toDouble() : null;
    final key = cleanAddress.toLowerCase();

    if (cleanAddress.isEmpty ||
        lat == null ||
        lng == null ||
        seen.contains(key)) {
      return;
    }

    seen.add(key);
    target.add(
      PlaceSuggestion(
        title: PlaceSuggestionService.primaryPlaceName(cleanAddress),
        subtitle: 'Used before',
        address: cleanAddress,
        latitude: lat,
        longitude: lng,
        isRecent: true,
      ),
    );
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
      await moveCamera(point, zoom: 16);

      if (!mounted) return;
      setState(() {
        selectedLocation = point;
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
    bool updateSearch = true,
  }) async {
    final nextAddress =
        address ??
        'Selected location (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})';

    setState(() {
      selectedLocation = point;
      selectedAddress = nextAddress;
      hasSelectedLocation = true;
      searchSuggestions = [];
      if (updateSearch) searchController.text = nextAddress;
    });

    if (animate) {
      await moveCamera(point, zoom: 16);
    }
  }

  Future<void> moveCamera(LatLng point, {double zoom = 16}) async {
    if (!mapController.isCompleted) return;

    final controller = await mapController.future;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: point, zoom: zoom)),
    );
  }

  void onSearchChanged(String value) {
    searchDebounce?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      setState(() => searchSuggestions = []);
      return;
    }

    searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;

      setState(() {
        hasSelectedLocation = false;
        searchSuggestions = PlaceSuggestionService.suggestionsFor(
          query,
          recent: recentSuggestions,
        );
      });
    });
  }

  Future<void> selectSuggestion(PlaceSuggestion suggestion) async {
    FocusScope.of(context).unfocus();
    await selectLocation(
      LatLng(suggestion.latitude, suggestion.longitude),
      address: suggestion.address,
      animate: true,
    );
  }

  Future<void> useCurrentLocation() async {
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
        locationMessage = message;
      });

      AppNotificationBannerService.error(message, title: 'Location needed');
      return;
    }

    if (mounted) setState(() => locationGranted = true);

    try {
      final position = await LocationService.getCurrentPosition();
      if (position == null) throw Exception('Location unavailable');

      final point = LatLng(position.latitude, position.longitude);
      await selectLocation(
        point,
        address:
            'Current location (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})',
        animate: true,
      );

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
        locationMessage = message;
      });

      AppNotificationBannerService.error(message, title: 'Location issue');
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
    searchDebounce?.cancel();
    searchController.dispose();
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
            onTap: (point) {
              FocusScope.of(context).unfocus();
              selectLocation(point, animate: false, updateSearch: false);
            },
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            decoration: const InputDecoration(
                              hintText:
                                  'Search city, road, estate, or landmark',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: onSearchChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Use current location',
                          onPressed: locating ? null : useCurrentLocation,
                          icon: locating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                if (searchSuggestions.isNotEmpty)
                  Card(
                    color: Colors.white,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 330),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: searchSuggestions.length,
                        itemBuilder: (context, index) {
                          final suggestion = searchSuggestions[index];
                          return _PlaceSuggestionTile(
                            suggestion: suggestion,
                            onTap: () => selectSuggestion(suggestion),
                          );
                        },
                      ),
                    ),
                  ),
              ],
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
                        selectedAddress.isEmpty
                            ? 'Search, use current location, or tap the map to choose the exact point.'
                            : selectedAddress,
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
                          if (!hasSelectedLocation) {
                            AppNotificationBannerService.error(
                              'Choose a suggestion, use current location, or tap the map to set the exact point.',
                              title: 'Select exact location',
                            );
                            return;
                          }

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

class _PlaceSuggestionTile extends StatelessWidget {
  const _PlaceSuggestionTile({required this.suggestion, required this.onTap});

  final PlaceSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Column(
                  children: [
                    Icon(
                      suggestion.isRecent
                          ? Icons.history_rounded
                          : Icons.location_on_outlined,
                      color: const Color(0xFF0F172A),
                    ),
                    if (suggestion.distanceLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        suggestion.distanceLabel!,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestion.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          suggestion.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
