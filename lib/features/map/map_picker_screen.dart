import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final MapController mapController = MapController();
  final TextEditingController searchController = TextEditingController();

  Timer? debounce;
  LatLng selectedLocation = const LatLng(6.5244, 3.3792);
  String selectedAddress = 'Selected location in Lagos';
  List<MapSearchResult> searchResults = [];
  bool isSearching = false;

  Future<void> searchPlaces(String value) async {
    final query = value.trim();

    if (query.length < 3) {
      setState(() => searchResults = []);
      return;
    }

    setState(() => isSearching = true);

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '5',
        'countrycodes': 'ng',
      });
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'EFATA logistics app'},
      );

      if (response.statusCode != 200) {
        throw Exception('Search failed');
      }

      final items = jsonDecode(response.body) as List<dynamic>;
      final results = items
          .map((item) {
            final map = item as Map<String, dynamic>;
            final lat = double.tryParse(map['lat']?.toString() ?? '');
            final lng = double.tryParse(map['lon']?.toString() ?? '');

            if (lat == null || lng == null) return null;

            return MapSearchResult(
              address: map['display_name']?.toString() ?? '',
              point: LatLng(lat, lng),
            );
          })
          .whereType<MapSearchResult>()
          .toList();

      if (!mounted) return;
      setState(() => searchResults = results);
    } finally {
      if (mounted) {
        setState(() => isSearching = false);
      }
    }
  }

  void onSearchChanged(String value) {
    debounce?.cancel();
    debounce = Timer(
      const Duration(milliseconds: 450),
      () => searchPlaces(value),
    );
  }

  void selectLocation(LatLng point, {String? address}) {
    setState(() {
      selectedLocation = point;
      selectedAddress =
          address ??
          'Selected location (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})';
      searchResults = [];
      searchController.text = selectedAddress;
    });
    mapController.move(point, 15);
  }

  @override
  void dispose() {
    debounce?.cancel();
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
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: selectedLocation,
              initialZoom: 13,
              onTap: (tapPosition, point) => selectLocation(point),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.logistics_app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: selectedLocation,
                    width: 48,
                    height: 48,
                    child: const Icon(
                      Icons.location_pin,
                      color: Color(0xFFDC2626),
                      size: 44,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.of(context).padding.top + 70,
            child: Column(
              children: [
                Material(
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search area, street, or landmark',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                if (searchResults.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Material(
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: searchResults.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 56),
                        itemBuilder: (context, index) {
                          final result = searchResults[index];

                          return ListTile(
                            leading: const Icon(Icons.place_outlined),
                            title: Text(
                              result.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => selectLocation(
                              result.point,
                              address: result.address,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: SafeArea(
              child: Card(
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

class MapSearchResult {
  const MapSearchResult({required this.address, required this.point});

  final String address;
  final LatLng point;
}
