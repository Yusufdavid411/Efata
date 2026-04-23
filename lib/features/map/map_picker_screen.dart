import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  LatLng selectedLocation = const LatLng(6.5244, 3.3792); // Lagos default

  @override
  Widget build(BuildContext context) {
    final locationText =
        'Selected location (${selectedLocation.latitude.toStringAsFixed(4)}, '
        '${selectedLocation.longitude.toStringAsFixed(4)})';

    return Scaffold(
      appBar: AppBar(title: const Text('Pick Location')),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: selectedLocation,
              initialZoom: 13,
              onTap: (tapPosition, point) {
                setState(() {
                  selectedLocation = point;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: selectedLocation,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.location_pin,
                      color: Colors.red,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 90,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  locationText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  {
                    'address': locationText,
                    'latitude': selectedLocation.latitude,
                    'longitude': selectedLocation.longitude,
                  },
                );
              },
              child: const Text('Confirm Location'),
            ),
          ),
        ],
      ),
    );
  }
}