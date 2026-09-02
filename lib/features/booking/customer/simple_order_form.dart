import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logistics_app/core/controllers/app_settings_controller.dart';
import 'package:logistics_app/features/map/map_picker_screen.dart';
import 'package:logistics_app/features/tracking/track_delivery_screen.dart';

class SimpleOrderForm extends StatefulWidget {
  const SimpleOrderForm({super.key});

  @override
  State<SimpleOrderForm> createState() => _SimpleOrderFormState();
}

class _SimpleOrderFormState extends State<SimpleOrderForm> {
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController dropoffController = TextEditingController();
  final TextEditingController itemController = TextEditingController();

  Timer? pickupDebounce;
  Timer? dropoffDebounce;

  List<PlaceSuggestion> pickupSuggestions = [];
  List<PlaceSuggestion> dropoffSuggestions = [];
  List<PlaceSuggestion> recentPickupSuggestions = [];
  List<PlaceSuggestion> recentDropoffSuggestions = [];

  String activeSearch = 'dropoff';
  String vehicleType = 'Truck';
  String paymentMethod = 'Cash on Delivery';
  String scheduleLabel = 'Pickup now';
  DateTime? scheduledPickupAt;

  bool isSubmitting = false;

  double? pickupLat;
  double? pickupLng;
  double? dropoffLat;
  double? dropoffLng;

  double distanceKm = 0;
  double estimatedPrice = 0;

  @override
  void initState() {
    super.initState();
    loadRecentPlaces();
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

      final pickupSeen = <String>{};
      final dropoffSeen = <String>{};
      final pickups = <PlaceSuggestion>[];
      final dropoffs = <PlaceSuggestion>[];

      for (final doc in docs) {
        final data = doc.data();
        _addRecentPlace(
          target: pickups,
          seen: pickupSeen,
          address: data['pickup'],
          latitude: data['pickupLat'],
          longitude: data['pickupLng'],
        );
        _addRecentPlace(
          target: dropoffs,
          seen: dropoffSeen,
          address: data['dropoff'],
          latitude: data['dropoffLat'],
          longitude: data['dropoffLng'],
        );
      }

      if (!mounted) return;

      setState(() {
        recentPickupSuggestions = pickups.take(6).toList();
        recentDropoffSuggestions = dropoffs.take(6).toList();
        pickupSuggestions = recentPickupSuggestions;
        dropoffSuggestions = _suggestionsFor('', isPickup: false);
      });
    } catch (_) {
      // Saved places are a convenience feature; booking still works with map pick.
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
        title: _primaryPlaceName(cleanAddress),
        subtitle: 'Used before',
        address: cleanAddress,
        latitude: lat,
        longitude: lng,
        isRecent: true,
      ),
    );
  }

  String _primaryPlaceName(String address) {
    final parts = address.split(',');
    return parts.first.trim().isEmpty ? address : parts.first.trim();
  }

  List<PlaceSuggestion> _suggestionsFor(String query, {required bool isPickup}) {
    final cleaned = query.trim().toLowerCase();
    final recent = isPickup ? recentPickupSuggestions : recentDropoffSuggestions;
    final source = [
      ...recent,
      ..._nigeriaPlaceCatalog.where((place) {
        return !recent.any(
          (recentPlace) =>
              recentPlace.address.toLowerCase() == place.address.toLowerCase(),
        );
      }),
    ];

    if (cleaned.isEmpty) return source.take(8).toList();

    final startsWith = source
        .where((place) => place.title.toLowerCase().startsWith(cleaned))
        .toList();
    final contains = source
        .where(
          (place) =>
              !startsWith.contains(place) &&
              place.address.toLowerCase().contains(cleaned),
        )
        .toList();

    return [...startsWith, ...contains].take(8).toList();
  }

  void onLocationTyped(String value, {required bool isPickup}) {
    final debounce = isPickup ? pickupDebounce : dropoffDebounce;
    debounce?.cancel();

    setState(() {
      activeSearch = isPickup ? 'pickup' : 'dropoff';
      if (isPickup) {
        pickupLat = null;
        pickupLng = null;
        pickupSuggestions = _suggestionsFor(value, isPickup: true);
      } else {
        dropoffLat = null;
        dropoffLng = null;
        dropoffSuggestions = _suggestionsFor(value, isPickup: false);
      }
      calculateDistanceAndPrice();
    });
  }

  void selectSuggestion(PlaceSuggestion suggestion, {required bool isPickup}) {
    setState(() {
      if (isPickup) {
        pickupController.text = suggestion.address;
        pickupLat = suggestion.latitude;
        pickupLng = suggestion.longitude;
        pickupSuggestions = _suggestionsFor('', isPickup: true);
      } else {
        dropoffController.text = suggestion.address;
        dropoffLat = suggestion.latitude;
        dropoffLng = suggestion.longitude;
        dropoffSuggestions = _suggestionsFor('', isPickup: false);
      }

      calculateDistanceAndPrice();
      FocusScope.of(context).unfocus();
    });
  }

  Future<void> openMapPicker(bool isPickup) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );

    if (!mounted) return;

    if (result != null && result is Map) {
      setState(() {
        if (isPickup) {
          pickupController.text = result['address']?.toString() ?? '';
          pickupLat = (result['latitude'] as num).toDouble();
          pickupLng = (result['longitude'] as num).toDouble();
        } else {
          dropoffController.text = result['address']?.toString() ?? '';
          dropoffLat = (result['latitude'] as num).toDouble();
          dropoffLng = (result['longitude'] as num).toDouble();
        }

        calculateDistanceAndPrice();
      });
    }
  }

  void calculateDistanceAndPrice() {
    if (pickupLat != null &&
        pickupLng != null &&
        dropoffLat != null &&
        dropoffLng != null) {
      final km =
          Geolocator.distanceBetween(
            pickupLat!,
            pickupLng!,
            dropoffLat!,
            dropoffLng!,
          ) /
          1000;

      distanceKm = km;
      estimatedPrice = 500 + (km * 100);
    } else {
      distanceKm = 0;
      estimatedPrice = 0;
    }
  }

  Future<void> submitOrder() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first')));
      return;
    }

    if (pickupController.text.isEmpty ||
        dropoffController.text.isEmpty ||
        itemController.text.isEmpty ||
        pickupLat == null ||
        pickupLng == null ||
        dropoffLat == null ||
        dropoffLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose pickup and drop-off from suggestions or map.'),
        ),
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      final docRef = await FirebaseFirestore.instance.collection('orders').add({
        'pickup': pickupController.text.trim(),
        'dropoff': dropoffController.text.trim(),
        'item': itemController.text.trim(),
        'vehicleType': vehicleType,
        'paymentMethod': paymentMethod,
        'paymentStatus': 'pending',
        'customerId': currentUser.uid,
        'driverId': null,
        'status': 'pending',
        'createdAt': Timestamp.now(),
        'pickupScheduleType': scheduledPickupAt == null ? 'now' : 'scheduled',
        'pickupScheduleLabel': scheduleLabel,
        'scheduledPickupAt': scheduledPickupAt == null
            ? null
            : Timestamp.fromDate(scheduledPickupAt!),
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        'dropoffLat': dropoffLat,
        'dropoffLng': dropoffLng,
        'driverLat': null,
        'driverLng': null,
        'distanceKm': distanceKm,
        'price': estimatedPrice,
        'unreadForCustomer': 0,
        'unreadForDriver': 0,
        'notificationStatus': 'created',
        'customerNotificationsEnabled':
            appSettingsController.orderNotificationsEnabled,
      });

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TrackDeliveryScreen(orderId: docRef.id),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  Future<void> openSchedulePicker() async {
    final result = await showModalBottomSheet<_PickupSchedule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => _SchedulePickupSheet(initialDate: scheduledPickupAt),
    );

    if (result == null) return;

    setState(() {
      scheduledPickupAt = result.dateTime;
      scheduleLabel = result.label;
    });
  }

  @override
  void dispose() {
    pickupDebounce?.cancel();
    dropoffDebounce?.cancel();
    pickupController.dispose();
    dropoffController.dispose();
    itemController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = activeSearch == 'pickup'
        ? pickupController.text.trim()
        : dropoffController.text.trim();
    final suggestions = activeSearch == 'pickup'
        ? pickupSuggestions
        : dropoffSuggestions;
    final activeIsPickup = activeSearch == 'pickup';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Where's it going?"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _RouteSearchHeader(
              scheduleLabel: scheduleLabel,
              pickupController: pickupController,
              dropoffController: dropoffController,
              pickupSelected: pickupLat != null,
              dropoffSelected: dropoffLat != null,
              onScheduleTap: openSchedulePicker,
              onPickupFocus: () {
                setState(() {
                  activeSearch = 'pickup';
                  pickupSuggestions = _suggestionsFor(
                    pickupController.text,
                    isPickup: true,
                  );
                });
              },
              onDropoffFocus: () {
                setState(() {
                  activeSearch = 'dropoff';
                  dropoffSuggestions = _suggestionsFor(
                    dropoffController.text,
                    isPickup: false,
                  );
                });
              },
              onPickupChanged: (value) =>
                  onLocationTyped(value, isPickup: true),
              onDropoffChanged: (value) =>
                  onLocationTyped(value, isPickup: false),
              onClearDropoff: () {
                setState(() {
                  dropoffController.clear();
                  dropoffLat = null;
                  dropoffLng = null;
                  dropoffSuggestions = _suggestionsFor('', isPickup: false);
                  calculateDistanceAndPrice();
                });
              },
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  if (suggestions.isEmpty && query.isNotEmpty)
                    _SearchActionTile(
                      icon: Icons.search_rounded,
                      title: 'Set "$query" on map',
                      subtitle: 'Drop the pin exactly where the driver should go.',
                      onTap: () => openMapPicker(activeIsPickup),
                    )
                  else
                    ...suggestions.map(
                      (suggestion) => _PlaceSuggestionTile(
                        suggestion: suggestion,
                        onTap: () => selectSuggestion(
                          suggestion,
                          isPickup: activeIsPickup,
                        ),
                      ),
                    ),
                  if (query.isNotEmpty) ...[
                    _SearchActionTile(
                      icon: Icons.search_rounded,
                      title: 'Get more results for $query',
                      subtitle: 'Use the map to confirm the exact point.',
                      onTap: () => openMapPicker(activeIsPickup),
                    ),
                  ],
                  _SearchActionTile(
                    icon: Icons.add_location_alt_outlined,
                    title: 'Set location on map',
                    subtitle: activeIsPickup
                        ? 'Choose the pickup point manually.'
                        : 'Choose the drop-off point manually.',
                    onTap: () => openMapPicker(activeIsPickup),
                  ),
                  const SizedBox(height: 12),
                  _ShipmentDetailsSection(
                    itemController: itemController,
                    vehicleType: vehicleType,
                    paymentMethod: paymentMethod,
                    onVehicleChanged: (value) {
                      if (value == null) return;
                      setState(() => vehicleType = value);
                    },
                    onPaymentChanged: (value) {
                      if (value == null) return;
                      setState(() => paymentMethod = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _EstimateCard(
                    distanceKm: distanceKm,
                    estimatedPrice: estimatedPrice,
                    paymentMethod: paymentMethod,
                    scheduleLabel: scheduleLabel,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: isSubmitting ? null : submitOrder,
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      isSubmitting ? 'Creating request...' : 'Request Delivery',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.title,
    required this.subtitle,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.distanceLabel,
    this.isRecent = false,
  });

  final String title;
  final String subtitle;
  final String address;
  final double latitude;
  final double longitude;
  final String? distanceLabel;
  final bool isRecent;
}

class _RouteSearchHeader extends StatelessWidget {
  const _RouteSearchHeader({
    required this.scheduleLabel,
    required this.pickupController,
    required this.dropoffController,
    required this.pickupSelected,
    required this.dropoffSelected,
    required this.onScheduleTap,
    required this.onPickupFocus,
    required this.onDropoffFocus,
    required this.onPickupChanged,
    required this.onDropoffChanged,
    required this.onClearDropoff,
  });

  final String scheduleLabel;
  final TextEditingController pickupController;
  final TextEditingController dropoffController;
  final bool pickupSelected;
  final bool dropoffSelected;
  final VoidCallback onScheduleTap;
  final VoidCallback onPickupFocus;
  final VoidCallback onDropoffFocus;
  final ValueChanged<String> onPickupChanged;
  final ValueChanged<String> onDropoffChanged;
  final VoidCallback onClearDropoff;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onScheduleTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_rounded, size: 19),
                    const SizedBox(width: 8),
                    Text(
                      scheduleLabel,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _RouteDots(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      _SearchField(
                        controller: pickupController,
                        hint: 'Pickup location',
                        selected: pickupSelected,
                        onTap: onPickupFocus,
                        onChanged: onPickupChanged,
                      ),
                      const SizedBox(height: 8),
                      _SearchField(
                        controller: dropoffController,
                        hint: 'Where to?',
                        selected: dropoffSelected,
                        onTap: onDropoffFocus,
                        onChanged: onDropoffChanged,
                        onClear: dropoffController.text.isEmpty
                            ? null
                            : onClearDropoff,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteDots extends StatelessWidget {
  const _RouteDots();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 82,
      child: Column(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFF94A3B8),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Container(
              width: 2,
              margin: const EdgeInsets.symmetric(vertical: 4),
              color: const Color(0xFFCBD5E1),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: Colors.black),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.selected,
    required this.onTap,
    required this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onTap: onTap,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF0F766E), width: 1.5),
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF16A34A),
                size: 19,
              ),
            if (onClear != null)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded),
                onPressed: onClear,
              ),
          ],
        ),
      ),
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 16,
        fontWeight: FontWeight.w700,
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                child: Column(
                  children: [
                    Icon(
                      suggestion.isRecent
                          ? Icons.history_rounded
                          : Icons.location_on_outlined,
                      color: Colors.black,
                    ),
                    if (suggestion.distanceLabel != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        suggestion.distanceLabel!,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestion.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          suggestion.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
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

class _SearchActionTile extends StatelessWidget {
  const _SearchActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFFF1F5F9),
        child: Icon(icon, color: Colors.black),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

class _ShipmentDetailsSection extends StatelessWidget {
  const _ShipmentDetailsSection({
    required this.itemController,
    required this.vehicleType,
    required this.paymentMethod,
    required this.onVehicleChanged,
    required this.onPaymentChanged,
  });

  final TextEditingController itemController;
  final String vehicleType;
  final String paymentMethod;
  final ValueChanged<String?> onVehicleChanged;
  final ValueChanged<String?> onPaymentChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delivery details',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: itemController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What are you sending?',
                hintText: 'Example: 20 bags of cement',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: vehicleType,
              decoration: const InputDecoration(
                labelText: 'Vehicle type',
                prefixIcon: Icon(Icons.local_shipping_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'Truck', child: Text('Truck')),
                DropdownMenuItem(value: 'Tipper', child: Text('Tipper')),
                DropdownMenuItem(
                  value: 'Petrol Tanker',
                  child: Text('Petrol Tanker'),
                ),
                DropdownMenuItem(value: 'Van', child: Text('Van')),
                DropdownMenuItem(value: 'Pickup', child: Text('Pickup')),
              ],
              onChanged: onVehicleChanged,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Cash on Delivery',
                  child: Text('Cash on Delivery'),
                ),
                DropdownMenuItem(
                  value: 'Bank Transfer',
                  child: Text('Bank Transfer'),
                ),
                DropdownMenuItem(
                  value: 'Pay on Pickup',
                  child: Text('Pay on Pickup'),
                ),
              ],
              onChanged: onPaymentChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({
    required this.distanceKm,
    required this.estimatedPrice,
    required this.paymentMethod,
    required this.scheduleLabel,
  });

  final double distanceKm;
  final double estimatedPrice;
  final String paymentMethod;
  final String scheduleLabel;

  @override
  Widget build(BuildContext context) {
    final hasEstimate = estimatedPrice > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasEstimate ? const Color(0xFFEFFDF6) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasEstimate
              ? const Color(0xFFBBF7D0)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          _SummaryRow(label: 'Pickup', value: scheduleLabel),
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Distance',
            value: '${distanceKm.toStringAsFixed(2)} km',
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Estimated price',
            value: 'NGN ${estimatedPrice.toStringAsFixed(0)}',
            isStrong: true,
          ),
          const SizedBox(height: 10),
          _SummaryRow(label: 'Payment', value: paymentMethod),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isStrong = false,
  });

  final String label;
  final String value;
  final bool isStrong;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: const Color(0xFF0F172A),
              fontSize: isStrong ? 18 : 14,
              fontWeight: isStrong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SchedulePickupSheet extends StatefulWidget {
  const _SchedulePickupSheet({required this.initialDate});

  final DateTime? initialDate;

  @override
  State<_SchedulePickupSheet> createState() => _SchedulePickupSheetState();
}

class _SchedulePickupSheetState extends State<_SchedulePickupSheet> {
  late DateTime selectedDay;
  late String selectedSlot;

  @override
  void initState() {
    super.initState();
    selectedDay = DateTime.now();
    selectedSlot = _timeSlots.first;
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(5, (index) {
      final day = DateTime.now().add(Duration(days: index));
      return DateTime(day.year, day.month, day.day);
    });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Schedule pickup',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: days.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final day = days[index];
                    final selected = _sameDay(day, selectedDay);
                    return _DayChoice(
                      label: index == 0
                          ? 'Today'
                          : index == 1
                              ? 'Tomorrow'
                              : _weekday(day),
                      date: '${_month(day)} ${day.day}',
                      selected: selected,
                      onTap: () => setState(() => selectedDay = day),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: _timeSlots.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  itemBuilder: (context, index) {
                    final slot = _timeSlots[index];
                    final selected = slot == selectedSlot;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        slot,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      trailing: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? Colors.black
                                : const Color(0xFF64748B),
                            width: selected ? 7 : 2,
                          ),
                        ),
                      ),
                      onTap: () => setState(() => selectedSlot = slot),
                    );
                  },
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(
                    context,
                    _PickupSchedule(
                      dateTime: _slotStart(selectedDay, selectedSlot),
                      label: '${_dayLabel(selectedDay)}, $selectedSlot',
                    ),
                  );
                },
                child: const Text('Select time'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                    const _PickupSchedule(
                      dateTime: null,
                      label: 'Pickup now',
                    ),
                  );
                },
                child: const Text('Pickup now'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    if (_sameDay(day, now)) return 'Today';
    if (_sameDay(day, tomorrow)) return 'Tomorrow';
    return '${_weekday(day)} ${_month(day)} ${day.day}';
  }

  DateTime _slotStart(DateTime day, String slot) {
    final firstPart = slot.split(' - ').first;
    final pieces = firstPart.split(' ');
    final hm = pieces.first.split(':');
    var hour = int.parse(hm.first);
    final minute = int.parse(hm.last);
    final period = pieces.last;

    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;

    return DateTime(day.year, day.month, day.day, hour, minute);
  }
}

class _DayChoice extends StatelessWidget {
  const _DayChoice({
    required this.label,
    required this.date,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String date;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.black : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(date, style: const TextStyle(color: Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }
}

class _PickupSchedule {
  const _PickupSchedule({required this.dateTime, required this.label});

  final DateTime? dateTime;
  final String label;
}

const _timeSlots = [
  '8:00 AM - 8:30 AM',
  '8:30 AM - 9:00 AM',
  '9:00 AM - 9:30 AM',
  '9:30 AM - 10:00 AM',
  '10:00 AM - 10:30 AM',
  '10:30 AM - 11:00 AM',
  '11:00 AM - 11:30 AM',
  '11:30 AM - 12:00 PM',
  '12:00 PM - 12:30 PM',
  '12:30 PM - 1:00 PM',
  '1:00 PM - 1:30 PM',
  '1:30 PM - 2:00 PM',
  '2:00 PM - 2:30 PM',
  '2:30 PM - 3:00 PM',
  '3:00 PM - 3:30 PM',
  '3:30 PM - 4:00 PM',
  '4:00 PM - 4:30 PM',
  '4:30 PM - 5:00 PM',
  '5:00 PM - 5:30 PM',
  '5:30 PM - 6:00 PM',
  '6:00 PM - 6:30 PM',
  '6:30 PM - 7:00 PM',
  '7:00 PM - 7:30 PM',
  '7:30 PM - 8:00 PM',
];

String _weekday(DateTime date) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return days[date.weekday - 1];
}

String _month(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[date.month - 1];
}

const _nigeriaPlaceCatalog = [
  PlaceSuggestion(
    title: 'Lagos Island',
    subtitle: 'Lagos, Nigeria',
    address: 'Lagos Island, Lagos, Nigeria',
    latitude: 6.4541,
    longitude: 3.3947,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Ikeja',
    subtitle: 'Lagos, Nigeria',
    address: 'Ikeja, Lagos, Nigeria',
    latitude: 6.6018,
    longitude: 3.3515,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Lekki Phase 1',
    subtitle: 'Lagos, Nigeria',
    address: 'Lekki Phase 1, Lagos, Nigeria',
    latitude: 6.4474,
    longitude: 3.4723,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Victoria Island',
    subtitle: 'Lagos, Nigeria',
    address: 'Victoria Island, Lagos, Nigeria',
    latitude: 6.4281,
    longitude: 3.4219,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Ajah',
    subtitle: 'Lagos, Nigeria',
    address: 'Ajah, Lagos, Nigeria',
    latitude: 6.4698,
    longitude: 3.5852,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Lugbe',
    subtitle: 'Abuja, Nigeria',
    address: 'Lugbe, Abuja, Nigeria',
    latitude: 9.0068,
    longitude: 7.3572,
    distanceLabel: '92 mi',
  ),
  PlaceSuggestion(
    title: 'Lugbe Plaza Abuja',
    subtitle: 'Abuja, Nigeria',
    address: 'Lugbe Plaza, Abuja, Nigeria',
    latitude: 9.0083,
    longitude: 7.3589,
    distanceLabel: '93 mi',
  ),
  PlaceSuggestion(
    title: 'CBN Quarters Lugbe',
    subtitle: 'Abuja, Nigeria',
    address: 'CBN Quarters Lugbe, Abuja, Nigeria',
    latitude: 9.0112,
    longitude: 7.3707,
    distanceLabel: '93 mi',
  ),
  PlaceSuggestion(
    title: 'Kaduna',
    subtitle: 'Nigeria',
    address: 'Kaduna, Nigeria',
    latitude: 10.5105,
    longitude: 7.4165,
    distanceLabel: '192 mi',
  ),
  PlaceSuggestion(
    title: 'Kaduna South',
    subtitle: 'Kaduna, Nigeria',
    address: 'Kaduna South, Kaduna, Nigeria',
    latitude: 10.4697,
    longitude: 7.4411,
    distanceLabel: '188 mi',
  ),
  PlaceSuggestion(
    title: 'Kaduna International Airport',
    subtitle: 'Kaduna, Nigeria',
    address: 'Kaduna International Airport, Kaduna, Nigeria',
    latitude: 10.696,
    longitude: 7.3201,
    distanceLabel: '203 mi',
  ),
  PlaceSuggestion(
    title: 'Lokaja International Stadium',
    subtitle: 'Lokoja, Kogi, Nigeria',
    address: 'Lokoja International Stadium, Lokoja, Kogi, Nigeria',
    latitude: 7.8093,
    longitude: 6.7388,
    distanceLabel: '154 mi',
  ),
  PlaceSuggestion(
    title: 'Federal University Lokoja',
    subtitle: 'Felele Campus, Lokoja, Nigeria',
    address: 'Federal University Lokoja, Felele Campus, Lokoja, Nigeria',
    latitude: 7.7542,
    longitude: 6.7551,
    distanceLabel: '151 mi',
  ),
];
