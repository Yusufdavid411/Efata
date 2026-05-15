import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AppLiveMap extends StatelessWidget {
  final LatLng pickupPoint;
  final LatLng dropoffPoint;
  final LatLng? driverPoint;

  const AppLiveMap({
    super.key,
    required this.pickupPoint,
    required this.dropoffPoint,
    required this.driverPoint,
  });

  @override
  Widget build(BuildContext context) {
    final mapCenter = driverPoint ?? pickupPoint;
    final routePoints = [
      if (driverPoint != null) driverPoint!,
      pickupPoint,
      dropoffPoint,
    ];

    return FlutterMap(
      key: ValueKey(
        '${mapCenter.latitude.toStringAsFixed(5)},${mapCenter.longitude.toStringAsFixed(5)}',
      ),
      options: MapOptions(initialCenter: mapCenter, initialZoom: 14),
      children: [
        TileLayer(
          urlTemplate: 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.logistics_app',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: routePoints,
              strokeWidth: 4,
              color: Colors.deepPurple,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: pickupPoint,
              width: 45,
              height: 45,
              child: const Icon(
                Icons.location_on,
                color: Colors.green,
                size: 42,
              ),
            ),
            Marker(
              point: dropoffPoint,
              width: 45,
              height: 45,
              child: const Icon(Icons.flag, color: Colors.red, size: 42),
            ),
            if (driverPoint != null)
              Marker(
                point: driverPoint!,
                width: 50,
                height: 50,
                child: const Icon(
                  Icons.local_shipping,
                  color: Colors.blue,
                  size: 42,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
