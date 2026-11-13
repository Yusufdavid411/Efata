import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/config/efata_backend_config.dart';
import '../../../../core/models/efata_api_models.dart';
import '../../../../core/services/efata_api_client.dart';

class CustomerSummaryCard extends StatelessWidget {
  const CustomerSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (EfataBackendConfig.useNewBackend) {
      return const _ApiCustomerSummaryCard();
    }
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('customerId', isEqualTo: user?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _CustomerSummaryLoading();
        }

        final orders = snapshot.data!.docs;
        int active = 0;
        int completed = 0;
        int pending = 0;

        for (final order in orders) {
          final data = order.data() as Map<String, dynamic>;
          final status = data['status']?.toString();
          if (status == 'completed') completed++;
          if (status == 'pending') pending++;
          if (status == 'accepted' || status == 'inTransit') active++;
        }

        return _SummaryContent(
          active: active,
          pending: pending,
          completed: completed,
        );
      },
    );
  }
}

class _ApiCustomerSummaryCard extends StatefulWidget {
  const _ApiCustomerSummaryCard();

  @override
  State<_ApiCustomerSummaryCard> createState() =>
      _ApiCustomerSummaryCardState();
}

class _ApiCustomerSummaryCardState extends State<_ApiCustomerSummaryCard> {
  late Future<List<EfataOrder>> _orders;

  @override
  void initState() {
    super.initState();
    _orders = EfataApiClient.instance.listAllOrders();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EfataOrder>>(
      future: _orders,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _CustomerSummaryLoading();
        }
        if (snapshot.hasError) {
          return _CustomerSummaryError(
            onRetry: () => setState(
              () => _orders = EfataApiClient.instance.listAllOrders(),
            ),
          );
        }

        var active = 0;
        var pending = 0;
        var completed = 0;
        for (final order in snapshot.data ?? const <EfataOrder>[]) {
          switch (_normalizeStatus(order.status)) {
            case 'pending':
              pending++;
            case 'accepted':
            case 'intransit':
              active++;
            case 'completed':
              completed++;
          }
        }

        return _SummaryContent(
          active: active,
          pending: pending,
          completed: completed,
        );
      },
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({
    required this.active,
    required this.pending,
    required this.completed,
  });

  final int active;
  final int pending;
  final int completed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Deliveries',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Active requests and delivery history in one place.',
            style: TextStyle(color: Color(0xFF64748B), height: 1.35),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _SummaryItem(
                icon: Icons.route_outlined,
                title: 'Active',
                value: active,
                color: const Color(0xFF0F766E),
              ),
              const SizedBox(width: 10),
              _SummaryItem(
                icon: Icons.schedule_outlined,
                title: 'Pending',
                value: pending,
                color: const Color(0xFFD97706),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SummaryItem(
                icon: Icons.check_circle_outline_rounded,
                title: 'Completed deliveries',
                value: completed,
                color: const Color(0xFF16A34A),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.toString(),
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 21,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
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

class _CustomerSummaryError extends StatelessWidget {
  const _CustomerSummaryError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: Color(0xFFDC2626)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delivery overview is temporarily unavailable.',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              onPressed: onRetry,
              tooltip: 'Retry',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

String _normalizeStatus(String status) =>
    status.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

class _CustomerSummaryLoading extends StatelessWidget {
  const _CustomerSummaryLoading();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: const [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Loading delivery overview',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
