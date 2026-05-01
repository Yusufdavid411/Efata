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

  Color getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'inTransit':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return "Waiting for driver";
      case 'accepted':
        return "Driver assigned";
      case 'inTransit':
        return "Driver is on the way";
      case 'completed':
        return "Delivery completed";
      case 'rejected':
        return "Rejected";
      default:
        return status;
    }
  }

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

          final pickup = data['pickup']?.toString() ?? 'No pickup';
          final dropoff = data['dropoff']?.toString() ?? 'No drop-off';
          final item = data['item']?.toString() ?? 'No item';
          final status = data['status']?.toString() ?? 'pending';

          final driverLat = data['driverLat'];
          final driverLng = data['driverLng'];

          final hasDriverLocation =
              driverLat != null && driverLng != null;

          final LatLng mapCenter = hasDriverLocation
              ? LatLng(
                  (driverLat as num).toDouble(),
                  (driverLng as num).toDouble(),
                )
              : const LatLng(6.5244, 3.3792); // Lagos fallback

          return Column(
            children: [
              Expanded(
                flex: 3,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: mapCenter,
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                    ),
                    MarkerLayer(
                      markers: [
                        if (hasDriverLocation)
                          Marker(
                            point: mapCenter,
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

              Expanded(
                flex: 2,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          color: getStatusColor(status),
                          size: 14,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          getStatusLabel(status),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Pickup: $pickup"),
                            const SizedBox(height: 8),
                            Text("Drop-off: $dropoff"),
                            const SizedBox(height: 8),
                            Text("Item: $item"),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (!hasDriverLocation)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Text(
                            "Driver location will appear here once the driver starts sharing location.",
                          ),
                        ),
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