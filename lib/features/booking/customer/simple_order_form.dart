import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:logistics_app/core/controllers/app_settings_controller.dart';
import 'package:logistics_app/features/map/map_picker_screen.dart';
import 'package:logistics_app/features/tracking/track_delivery_screen.dart';

const String googlePlacesApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

class SimpleOrderForm extends StatefulWidget {
  const SimpleOrderForm({super.key});

  @override
  State<SimpleOrderForm> createState() => _SimpleOrderFormState();
}

class _SimpleOrderFormState extends State<SimpleOrderForm> {
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController dropoffController = TextEditingController();
  final TextEditingController itemController = TextEditingController();

  final Distance distance = const Distance();

  Timer? pickupDebounce;
  Timer? dropoffDebounce;

  List<PlaceSuggestion> pickupSuggestions = [];
  List<PlaceSuggestion> dropoffSuggestions = [];

  String vehicleType = 'Truck';
  String paymentMethod = 'Cash on Delivery';

  bool isSearchingPickup = false;
  bool isSearchingDropoff = false;
  bool isSubmitting = false;

  double? pickupLat;
  double? pickupLng;
  double? dropoffLat;
  double? dropoffLng;

  double distanceKm = 0;
  double estimatedPrice = 0;

  Future<void> searchPlaces(String query, {required bool isPickup}) async {
    final cleanedQuery = query.trim();

    if (cleanedQuery.length < 3) {
      setState(() {
        if (isPickup) {
          pickupSuggestions = [];
        } else {
          dropoffSuggestions = [];
        }
      });
      return;
    }

    setState(() {
      if (isPickup) {
        isSearchingPickup = true;
      } else {
        isSearchingDropoff = true;
      }
    });

    try {
      final suggestions = googlePlacesApiKey.isNotEmpty
          ? await GooglePlacesService.search(cleanedQuery)
          : await OpenStreetMapPlacesService.search(cleanedQuery);

      if (!mounted) return;

      setState(() {
        if (isPickup) {
          pickupSuggestions = suggestions;
        } else {
          dropoffSuggestions = suggestions;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (isPickup) {
          pickupSuggestions = [];
        } else {
          dropoffSuggestions = [];
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          if (isPickup) {
            isSearchingPickup = false;
          } else {
            isSearchingDropoff = false;
          }
        });
      }
    }
  }

  void onLocationTyped(String value, {required bool isPickup}) {
    final debounce = isPickup ? pickupDebounce : dropoffDebounce;
    debounce?.cancel();

    if (isPickup) {
      pickupLat = null;
      pickupLng = null;
      pickupDebounce = Timer(
        const Duration(milliseconds: 450),
        () => searchPlaces(value, isPickup: true),
      );
    } else {
      dropoffLat = null;
      dropoffLng = null;
      dropoffDebounce = Timer(
        const Duration(milliseconds: 450),
        () => searchPlaces(value, isPickup: false),
      );
    }

    setState(() {
      calculateDistanceAndPrice();
    });
  }

  Future<void> selectSuggestion(
    PlaceSuggestion suggestion, {
    required bool isPickup,
  }) async {
    PlaceSuggestion selected = suggestion;

    if (googlePlacesApiKey.isNotEmpty && suggestion.placeId != null) {
      selected = await GooglePlacesService.details(suggestion);
    }

    if (!mounted) return;

    setState(() {
      if (isPickup) {
        pickupController.text = selected.address;
        pickupLat = selected.latitude;
        pickupLng = selected.longitude;
        pickupSuggestions = [];
      } else {
        dropoffController.text = selected.address;
        dropoffLat = selected.latitude;
        dropoffLng = selected.longitude;
        dropoffSuggestions = [];
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
          pickupSuggestions = [];
        } else {
          dropoffController.text = result['address']?.toString() ?? '';
          dropoffLat = (result['latitude'] as num).toDouble();
          dropoffLng = (result['longitude'] as num).toDouble();
          dropoffSuggestions = [];
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
      final km = distance.as(
        LengthUnit.Kilometer,
        LatLng(pickupLat!, pickupLng!),
        LatLng(dropoffLat!, dropoffLng!),
      );

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
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        'dropoffLat': dropoffLat,
        'dropoffLng': dropoffLng,
        'driverLat': null,
        'driverLng': null,
        'distanceKm': distanceKm,
        'price': estimatedPrice,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Create delivery')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _BookingHeader(),
            const SizedBox(height: 18),
            _SectionCard(
              title: 'Route',
              subtitle: 'Type an address or pick directly from the map.',
              child: Column(
                children: [
                  _LocationInput(
                    label: 'Pickup location',
                    hint: 'Start typing pickup address',
                    controller: pickupController,
                    icon: Icons.my_location_rounded,
                    isSelected: pickupLat != null,
                    isLoading: isSearchingPickup,
                    suggestions: pickupSuggestions,
                    onChanged: (value) =>
                        onLocationTyped(value, isPickup: true),
                    onMapTap: () => openMapPicker(true),
                    onSuggestionTap: (suggestion) =>
                        selectSuggestion(suggestion, isPickup: true),
                  ),
                  const SizedBox(height: 16),
                  _LocationInput(
                    label: 'Drop-off location',
                    hint: 'Start typing destination',
                    controller: dropoffController,
                    icon: Icons.flag_rounded,
                    isSelected: dropoffLat != null,
                    isLoading: isSearchingDropoff,
                    suggestions: dropoffSuggestions,
                    onChanged: (value) =>
                        onLocationTyped(value, isPickup: false),
                    onMapTap: () => openMapPicker(false),
                    onSuggestionTap: (suggestion) =>
                        selectSuggestion(suggestion, isPickup: false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'Shipment details',
              subtitle: 'Tell the driver what vehicle and handling to expect.',
              child: Column(
                children: [
                  TextField(
                    controller: itemController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Item description',
                      hintText: 'Example: 20 bags of cement',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => vehicleType = value);
                    },
                  ),
                  const SizedBox(height: 16),
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
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => paymentMethod = value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _EstimateCard(
              distanceKm: distanceKm,
              estimatedPrice: estimatedPrice,
              paymentMethod: paymentMethod,
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: isSubmitting ? null : submitOrder,
              icon: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: Text(isSubmitting ? 'Creating order...' : 'Create Order'),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.address,
    this.latitude,
    this.longitude,
    this.placeId,
  });

  final String address;
  final double? latitude;
  final double? longitude;
  final String? placeId;
}

class GooglePlacesService {
  static Future<List<PlaceSuggestion>> search(String query) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {'input': query, 'components': 'country:ng', 'key': googlePlacesApiKey},
    );
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Google Places request failed');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final predictions = body['predictions'] as List<dynamic>? ?? [];

    return predictions
        .map(
          (item) => PlaceSuggestion(
            address: item['description']?.toString() ?? '',
            placeId: item['place_id']?.toString(),
          ),
        )
        .where((item) => item.address.isNotEmpty)
        .toList();
  }

  static Future<PlaceSuggestion> details(PlaceSuggestion suggestion) async {
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
          'place_id': suggestion.placeId!,
          'fields': 'formatted_address,geometry',
          'key': googlePlacesApiKey,
        });
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      return suggestion;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final result = body['result'] as Map<String, dynamic>? ?? {};
    final location =
        (result['geometry'] as Map<String, dynamic>?)?['location']
            as Map<String, dynamic>?;

    return PlaceSuggestion(
      address: result['formatted_address']?.toString() ?? suggestion.address,
      latitude: (location?['lat'] as num?)?.toDouble(),
      longitude: (location?['lng'] as num?)?.toDouble(),
      placeId: suggestion.placeId,
    );
  }
}

class OpenStreetMapPlacesService {
  static Future<List<PlaceSuggestion>> search(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '6',
      'countrycodes': 'ng',
      'addressdetails': '1',
    });
    final response = await http.get(
      uri,
      headers: const {'User-Agent': 'EFATA logistics app'},
    );

    if (response.statusCode != 200) {
      throw Exception('Place search failed');
    }

    final items = jsonDecode(response.body) as List<dynamic>;

    return items
        .map((item) {
          final map = item as Map<String, dynamic>;
          return PlaceSuggestion(
            address: map['display_name']?.toString() ?? '',
            latitude: double.tryParse(map['lat']?.toString() ?? ''),
            longitude: double.tryParse(map['lon']?.toString() ?? ''),
          );
        })
        .where(
          (item) =>
              item.address.isNotEmpty &&
              item.latitude != null &&
              item.longitude != null,
        )
        .toList();
  }
}

class _BookingHeader extends StatelessWidget {
  const _BookingHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        children: [
          Icon(Icons.route_rounded, color: Colors.white, size: 34),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Book a delivery',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Confirm route, vehicle, payment, and price before request.',
                  style: TextStyle(color: Color(0xFFCBD5E1), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF64748B), height: 1.35),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _LocationInput extends StatelessWidget {
  const _LocationInput({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    required this.isSelected,
    required this.isLoading,
    required this.suggestions,
    required this.onChanged,
    required this.onMapTap,
    required this.onSuggestionTap,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData icon;
  final bool isSelected;
  final bool isLoading;
  final List<PlaceSuggestion> suggestions;
  final ValueChanged<String> onChanged;
  final VoidCallback onMapTap;
  final ValueChanged<PlaceSuggestion> onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF16A34A),
                size: 18,
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                IconButton(
                  tooltip: 'Pick on map',
                  icon: const Icon(Icons.map_outlined),
                  color: colors.primary,
                  onPressed: onMapTap,
                ),
              ],
            ),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: suggestions
                  .map(
                    (suggestion) => ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.place_outlined,
                        color: colors.primary,
                      ),
                      title: Text(
                        suggestion.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () => onSuggestionTap(suggestion),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({
    required this.distanceKm,
    required this.estimatedPrice,
    required this.paymentMethod,
  });

  final double distanceKm;
  final double estimatedPrice;
  final String paymentMethod;

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
          const SizedBox(height: 12),
          const Text(
            'Online checkout will be connected after payment integration. For now, the selected payment method is saved with the order.',
            style: TextStyle(color: Color(0xFF64748B), height: 1.35),
          ),
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
