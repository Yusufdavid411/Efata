import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _apiOrigin = String.fromEnvironment('EFATA_API_ORIGIN');

class OrderHistoryPreview extends StatefulWidget {
  const OrderHistoryPreview({super.key, required this.isDriver});

  final bool isDriver;
  static bool get enabled => _apiOrigin.isNotEmpty;

  @override
  State<OrderHistoryPreview> createState() => _OrderHistoryPreviewState();
}

class _OrderHistoryPreviewState extends State<OrderHistoryPreview> {
  late Future<Map<String, dynamic>> _request = _load();

  Future<Map<String, dynamic>> _load() async {
    final base = Uri.tryParse(_apiOrigin);
    if (base == null ||
        !base.hasAuthority ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        (base.path.isNotEmpty && base.path != '/') ||
        base.hasQuery ||
        base.hasFragment ||
        (base.scheme != 'https' &&
            !(kDebugMode &&
                base.scheme == 'http' &&
                ['127.0.0.1', '10.0.2.2', 'localhost'].contains(base.host)))) {
      throw StateError('Invalid API origin');
    }

    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    final token = await user?.getIdToken();
    if (token == null || auth.currentUser?.uid != user?.uid) {
      throw StateError('No active sign-in');
    }
    final client = http.Client();
    try {
      final request =
          http.Request(
              'GET',
              base.replace(
                path: '/api/order-history',
                queryParameters: {
                  'scope': widget.isDriver ? 'driver' : 'customer',
                },
              ),
            )
            ..followRedirects = false
            ..headers['Authorization'] = 'Bearer $token';
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || auth.currentUser?.uid != user?.uid) {
        throw StateError('Order history unavailable');
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  String _status(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return 'Unknown status';
    if (value == 'inTransit') return 'In transit';
    return value[0].toUpperCase() + value.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _request,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load the order history preview.'),
                TextButton(
                  onPressed: () => setState(() => _request = _load()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final result = snapshot.requireData;
        final date = DateTime.tryParse(
          result['asOf']?.toString() ?? '',
        )?.toLocal();
        final orders = (result['orders'] as List).cast<Map<String, dynamic>>();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Order history preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (date != null)
              Text(
                'Snapshot: ${MaterialLocalizations.of(context).formatMediumDate(date)}',
              ),
            const Divider(),
            if (orders.isEmpty)
              const ListTile(title: Text('No orders in this snapshot')),
            for (final order in orders)
              ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(order['dropoff']?.toString() ?? 'Delivery'),
                subtitle: Text(
                  [
                    if (order['pickup'] != null) 'From ${order['pickup']}',
                    _status(order['status']),
                  ].join('\n'),
                ),
              ),
          ],
        );
      },
    );
  }
}
