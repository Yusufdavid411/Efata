import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class LiveTrackingScreen extends StatelessWidget {
  final String orderId;

  const LiveTrackingScreen({
    super.key,
    required this.orderId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text('Order not found'),
            );
          }

          final order = snapshot.data!.data() as Map<String, dynamic>;

          final pickupLat = order['pickupLat'];
          final pickupLng = order['pickupLng'];
          final dropoffLat = order['dropoffLat'];
          final dropoffLng = order['dropoffLng'];
          final driverLat = order['driverLat'];
          final driverLng = order['driverLng'];
          final status = order['status'] ?? 'pending';

          if (pickupLat == null ||
              pickupLng == null ||
              dropoffLat == null ||
              dropoffLng == null) {
            return const Center(
              child: Text('Location data is missing'),
            );
          }

          final pickupPoint = LatLng(pickupLat, pickupLng);
          final dropoffPoint = LatLng(dropoffLat, dropoffLng);

          final driverPoint = driverLat != null && driverLng != null
              ? LatLng(driverLat, driverLng)
              : null;

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.blue.shade50,
                child: Text(
                  'Order Status: $status',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: driverPoint ?? pickupPoint,
                    initialZoom: 13,
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