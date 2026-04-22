import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logistics_app/features/booking/customer/track_delivery_screen.dart';
import 'package:logistics_app/features/map/map_picker_screen.dart';

class SimpleOrderForm extends StatefulWidget {
  const SimpleOrderForm({super.key});

  @override
  State<SimpleOrderForm> createState() => _SimpleOrderFormState();
}

class _SimpleOrderFormState extends State<SimpleOrderForm> {
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController dropoffController = TextEditingController();
  final TextEditingController itemController = TextEditingController();

  Future<void> openMapPicker(bool isPickup) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MapPickerScreen(),
      ),
    );

    if (!mounted) return;

    if (result != null && result is String) {
      setState(() {
        if (isPickup) {
          pickupController.text = result;
        } else {
          dropoffController.text = result;
        }
      });
    }
  }

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

    final docRef =
        await FirebaseFirestore.instance.collection('orders').add({
      'pickup': pickupController.text.trim(),
      'dropoff': dropoffController.text.trim(),
      'item': itemController.text.trim(),
      'customerId': currentUser!.uid,
      'driverId': null,
      'status': 'pending',
      'createdAt': Timestamp.now(),
    });

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TrackDeliveryScreen(orderId: docRef.id),
      ),
    );
  }

  Widget locationField({
    required String label,
    required TextEditingController controller,
    required VoidCallback onMapTap,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.map),
          onPressed: onMapTap,
        ),
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
              controller: pickupController,
              onMapTap: () => openMapPicker(true),
            ),
            const SizedBox(height: 16),
            locationField(
              label: 'Drop-off Location',
              controller: dropoffController,
              onMapTap: () => openMapPicker(false),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: itemController,
              decoration: const InputDecoration(
                labelText: 'Item Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
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