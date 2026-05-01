import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class DriverActiveJobsScreen extends StatefulWidget {
  const DriverActiveJobsScreen({super.key});

  @override
  State<DriverActiveJobsScreen> createState() => _DriverActiveJobsScreenState();
}

class _DriverActiveJobsScreenState extends State<DriverActiveJobsScreen> {
  StreamSubscription<Position>? locationSubscription;
  String? trackingOrderId;

  Future<void> startTransit(String id) async {
    await FirebaseFirestore.instance.collection('orders').doc(id).update({
      'status': 'inTransit',
      'startedAt': Timestamp.now(),
    });

    startLiveLocationTracking(id);
  }

  Future<void> completeJob(String id) async {
    await locationSubscription?.cancel();
    locationSubscription = null;
    trackingOrderId = null;

    await FirebaseFirestore.instance.collection('orders').doc(id).update({
      'status': 'completed',
      'completedAt': Timestamp.now(),
    });
  }

  Future<bool> ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please turn on your location service")),
        );
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission is required")),
        );
      }
      return false;
    }

    return true;
  }

  Future<void> startLiveLocationTracking(String orderId) async {
    if (trackingOrderId == orderId && locationSubscription != null) return;

    final allowed = await ensureLocationPermission();
    if (!allowed) return;

    await locationSubscription?.cancel();

    trackingOrderId = orderId;

    locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((position) {
      FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'driverLat': position.latitude,
        'driverLng': position.longitude,
        'lastLocationUpdate': Timestamp.now(),
      });
    });
  }

  String formatTime(dynamic ts) {
    if (ts == null || ts is! Timestamp) return 'Not available';

    final d = ts.toDate();
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');

    return "${d.day}/${d.month}/${d.year} at $hour:$minute";
  }

  @override
  void dispose() {
    locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Current Job")),
        body: const Center(child: Text("Driver not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Current Job"),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('driverId', isEqualTo: driver.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          final active = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'];
            return status == 'accepted' || status == 'inTransit';
          }).toList();

          if (active.isEmpty) {
            return const Center(child: Text("No active job"));
          }

          final job = active.first;
          final data = job.data() as Map<String, dynamic>;

          final pickup = data['pickup']?.toString() ?? 'No pickup';
          final dropoff = data['dropoff']?.toString() ?? 'No drop-off';
          final item = data['item']?.toString() ?? 'No item';
          final status = data['status']?.toString() ?? 'accepted';
          final price = data['price'];
          final createdAt = data['createdAt'];

          if (status == 'inTransit') {
            startLiveLocationTracking(job.id);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Delivery Details",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 16),

                      Text("Pickup: $pickup"),
                      const SizedBox(height: 8),
                      Text("Drop-off: $dropoff"),
                      const SizedBox(height: 8),
                      Text("Item: $item"),
                      const SizedBox(height: 8),
                      Text("Status: $status"),
                      const SizedBox(height: 8),
                      Text("Created: ${formatTime(createdAt)}"),

                      if (price != null) ...[
                        const SizedBox(height: 8),
                        Text("Price: ₦$price"),
                      ],

                      const SizedBox(height: 24),

                      if (status == 'accepted')
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => startTransit(job.id),
                            child: const Text("Start Transit"),
                          ),
                        ),

                      if (status == 'inTransit')
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => completeJob(job.id),
                            child: const Text("Mark Completed"),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}