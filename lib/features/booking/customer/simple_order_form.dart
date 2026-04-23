import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logistics_app/features/booking/customer/track_delivery_screen.dart';
import 'package:logistics_app/features/map/map_picker_screen.dart';
import 'package:latlong2/latlong.dart';

class SimpleOrderForm extends StatefulWidget {
  const SimpleOrderForm({super.key});

  @override
  State<SimpleOrderForm> createState() => _SimpleOrderFormState();
}

class _SimpleOrderFormState extends State<SimpleOrderForm> {
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController dropoffController = TextEditingController();
  final TextEditingController itemController = TextEditingController();

  // ✅ Coordinates
  double? pickupLat;
  double? pickupLng;
  double? dropoffLat;
  double? dropoffLng;

  // ✅ Distance & Price
  double distanceKm = 0;
  double estimatedPrice = 0;

  final Distance distance = Distance();

  // ================= MAP PICKER =================
  Future<void> openMapPicker(bool isPickup) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MapPickerScreen(),
      ),
    );

    if (!mounted) return;

    if (result != null && result is Map) {
      setState(() {
        if (isPickup) {
          pickupController.text = result['address'];
          pickupLat = result['latitude'];
          pickupLng = result['longitude'];
        } else {
          dropoffController.text = result['address'];
          dropoffLat = result['latitude'];
          dropoffLng = result['longitude'];
        }

        calculateDistanceAndPrice();
      });
    }
  }

  // ================= DISTANCE + PRICE =================
  void calculateDistanceAndPrice() {
    if (pickupLat != null &&
        pickupLng != null &&
        dropoffLat != null &&
        dropoffLng != null) {

      final km = distance.as(
        LengthUnit.Kilometer,
        LatLng(pickupLat!, pickupLng!),
        LatLng(dropoffLat!, dropoffLng!),
      );

      setState(() {
        distanceKm = km;
        estimatedPrice = 500 + (km * 100); // simple pricing
      });
    }
  }

  // ================= SUBMIT ORDER =================
  Future<void> submitOrder() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (pickupController.text.isEmpty ||
        dropoffController.text.isEmpty ||
        itemController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete all fields")),
      );
      return;
    }

    final docRef = await FirebaseFirestore.instance.collection('orders').add({
      'pickup': pickupController.text.trim(),
      'dropoff': dropoffController.text.trim(),
      'item': itemController.text.trim(),
      'customerId': currentUser!.uid,
      'driverId': null,
      'status': 'pending',
      'createdAt': Timestamp.now(),

      // ✅ NEW DATA
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'distanceKm': distanceKm,
      'price': estimatedPrice,
    });

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TrackDeliveryScreen(orderId: docRef.id),
      ),
    );
  }

  // ================= UI HELPERS =================
  Widget locationField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required VoidCallback onMapTap,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: hint,
                  prefixIcon: Icon(icon),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: const Icon(Icons.map),
              onPressed: onMapTap,
            ),
          ],
        ),
      ],
    );
  }

  Widget summaryRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(value),
      ],
    );
  }

  @override
  void dispose() {
    pickupController.dispose();
    dropoffController.dispose();
    itemController.dispose();
    super.dispose();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Delivery')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            locationField(
              label: 'Pickup Location',
              hint: 'Select pickup',
              controller: pickupController,
              onMapTap: () => openMapPicker(true),
              icon: Icons.location_on,
            ),
            const SizedBox(height: 16),
            locationField(
              label: 'Drop-off Location',
              hint: 'Select drop-off',
              controller: dropoffController,
              onMapTap: () => openMapPicker(false),
              icon: Icons.flag,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: itemController,
              decoration: const InputDecoration(
                labelText: 'Item Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // ✅ PRICE SECTION
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    summaryRow('Distance', '${distanceKm.toStringAsFixed(2)} km'),
                    const SizedBox(height: 6),
                    summaryRow(
                      'Estimated Price',
                      '₦${estimatedPrice.toStringAsFixed(0)}',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: submitOrder,
              child: const Text('Submit Order'),
            ),
          ],
        ),
      ),
    );
  }
}