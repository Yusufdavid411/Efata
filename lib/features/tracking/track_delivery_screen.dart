import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class TrackDeliveryScreen extends StatelessWidget {
  final String orderId;

  const TrackDeliveryScreen({
    super.key,
    required this.orderId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Delivery'),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final pickupLat = data['pickupLat'];
          final pickupLng = data['pickupLng'];

          final dropoffLat = data['dropoffLat'];
          final dropoffLng = data['dropoffLng'];

          final driverLat = data['driverLat'];
          final driverLng = data['driverLng'];

          final status = data['status'] ?? 'pending';

          if (pickupLat == null || dropoffLat == null) {
            return const Center(
              child: Text("Location data missing"),
            );
          }

          final pickupPoint =
              LatLng((pickupLat as num).toDouble(), (pickupLng as num).toDouble());

          final dropoffPoint =
              LatLng((dropoffLat as num).toDouble(), (dropoffLng as num).toDouble());

          final driverPoint = (driverLat != null && driverLng != null)
              ? LatLng((driverLat as num).toDouble(),
                  (driverLng as num).toDouble())
              : null;

          final center = driverPoint ?? pickupPoint;

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.blue.shade50,
                child: Text(
                  "Status: $status",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                    ),

                    MarkerLayer(
                      markers: [
                        Marker(
                          point: pickupPoint,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.green,
                            size: 40,
                          ),
                        ),

                        Marker(
                          point: dropoffPoint,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.flag,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),

                        if (driverPoint != null)
                          Marker(
                            point: driverPoint,
                            width: 45,
                            height: 45,
                            child: const Icon(
                              Icons.local_shipping,
                              color: Colors.blue,
                              size: 40,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}