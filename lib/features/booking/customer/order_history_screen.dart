import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/config/efata_backend_config.dart';
import '../../../core/models/efata_api_models.dart';
import '../../../core/services/efata_api_client.dart';
import '../../../shared/widgets/app_bottom_navigation.dart';
import '../../../shared/widgets/order_history_preview.dart';
import 'widgets/active_delivery_section.dart';

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const AppBottomNavigation(
        isDriver: false,
        currentIndex: 2,
      ),
      body: const OrderHistoryContent(),
    );
  }
}

class OrderHistoryContent extends StatelessWidget {
  const OrderHistoryContent({super.key});

  bool isCurrentOrder(QueryDocumentSnapshot order) {
    final data = order.data() as Map<String, dynamic>;
    final status = (data['status']?.toString() ?? '').toLowerCase().replaceAll(
      RegExp(r'[\s_-]+'),
      '',
    );
    return status == 'pending' || status == 'accepted' || status == 'intransit';
  }

  @override
  Widget build(BuildContext context) {
    if (OrderHistoryPreview.enabled) {
      return const OrderHistoryPreview(isDriver: false);
    }
    if (EfataBackendConfig.useNewBackend) {
      return const _ApiOrderHistoryContent();
    }
    final currentUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('customerId', isEqualTo: currentUser?.uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(child: Text('Something went wrong'));
        }

        final orders = snapshot.data?.docs ?? [];

        if (orders.isEmpty) {
          return const Center(child: Text('No orders yet'));
        }

        final currentOrders = orders.where(isCurrentOrder).toList();
        final previousOrders = orders
            .where((order) => !isCurrentOrder(order))
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (currentOrders.isNotEmpty) ...[
              const _SectionTitle(title: 'Current order'),
              ...currentOrders.map(
                (order) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OrderPreviewCard(
                    order: order,
                    title: currentOrders.first == order ? 'Active now' : null,
                    isPrimary: currentOrders.first == order,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (previousOrders.isNotEmpty) ...[
              const _SectionTitle(title: 'Previous orders'),
              ...previousOrders.map(
                (order) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OrderPreviewCard(order: order),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ApiOrderHistoryContent extends StatefulWidget {
  const _ApiOrderHistoryContent();

  @override
  State<_ApiOrderHistoryContent> createState() =>
      _ApiOrderHistoryContentState();
}

class _ApiOrderHistoryContentState extends State<_ApiOrderHistoryContent> {
  late Future<List<EfataOrder>> _orders;

  @override
  void initState() {
    super.initState();
    _orders = EfataApiClient.instance.listAllOrders();
  }

  Future<void> _refresh() async {
    final next = EfataApiClient.instance.listAllOrders();
    setState(() => _orders = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EfataOrder>>(
      future: _orders,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _OrderHistoryError(onRetry: _refresh);
        }

        final orders = snapshot.data ?? const <EfataOrder>[];
        if (orders.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 180),
                Center(child: Text('No orders yet')),
              ],
            ),
          );
        }

        final currentOrders = orders.where(_isCurrentApiOrder).toList();
        final previousOrders = orders
            .where((o) => !_isCurrentApiOrder(o))
            .toList();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (currentOrders.isNotEmpty) ...[
                const _SectionTitle(title: 'Current order'),
                ...currentOrders.map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OrderPreviewCard.api(
                      order: order,
                      title: currentOrders.first == order ? 'Active now' : null,
                      isPrimary: currentOrders.first == order,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (previousOrders.isNotEmpty) ...[
                const _SectionTitle(title: 'Previous orders'),
                ...previousOrders.map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OrderPreviewCard.api(order: order),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

bool _isCurrentApiOrder(EfataOrder order) {
  final status = order.status.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  return status == 'pending' || status == 'accepted' || status == 'intransit';
}

class _OrderHistoryError extends StatelessWidget {
  const _OrderHistoryError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFDC2626),
              size: 36,
            ),
            const SizedBox(height: 12),
            const Text(
              'Orders could not load.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
