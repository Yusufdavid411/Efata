import 'package:flutter/material.dart';

import '../../../core/models/efata_api_models.dart';
import '../../../core/services/efata_api_client.dart';

class DriverEarningsSummary extends StatelessWidget {
  const DriverEarningsSummary({super.key});

  void showWithdrawalProcess(BuildContext context, double amount) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Withdraw earnings',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Available balance: NGN ${amount.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Color(0xFF0F766E),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              const _PayoutStep(
                icon: Icons.account_balance_outlined,
                title: 'Bank account',
                body: 'Add or confirm the bank account that receives payouts.',
              ),
              const _PayoutStep(
                icon: Icons.verified_user_outlined,
                title: 'Admin review',
                body: 'EFATA verifies the payout request before processing.',
              ),
              const _PayoutStep(
                icon: Icons.payments_outlined,
                title: 'Payout record',
                body: 'The dashboard will keep the payout status and receipt.',
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: amount <= 0 ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Request Payout'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ApiDriverEarningsSummary(
      onWithdraw: (amount) => showWithdrawalProcess(context, amount),
    );
  }
}

class _ApiDriverEarningsSummary extends StatefulWidget {
  const _ApiDriverEarningsSummary({required this.onWithdraw});

  final ValueChanged<double> onWithdraw;

  @override
  State<_ApiDriverEarningsSummary> createState() =>
      _ApiDriverEarningsSummaryState();
}

class _ApiDriverEarningsSummaryState extends State<_ApiDriverEarningsSummary> {
  late Future<List<EfataOrder>> _orders;

  @override
  void initState() {
    super.initState();
    _orders = EfataApiClient.instance.listAllOrders(status: 'completed');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EfataOrder>>(
      future: _orders,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _EarningsSkeleton();
        }
        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Earnings could not load. Please try again.'),
            ),
          );
        }
        final jobs = snapshot.data ?? const <EfataOrder>[];
        final now = DateTime.now();
        var total = 0.0;
        var month = 0.0;
        for (final job in jobs) {
          total += job.amount;
          final completedAt = job.completedAt?.toLocal();
          if (completedAt != null &&
              completedAt.year == now.year &&
              completedAt.month == now.month) {
            month += job.amount;
          }
        }
        return _EarningsWalletContent(
          totalEarnings: total,
          monthEarnings: month,
          completedCount: jobs.length,
          onWithdraw: () => widget.onWithdraw(total),
        );
      },
    );
  }
}

class _EarningsWalletContent extends StatelessWidget {
  const _EarningsWalletContent({
    required this.totalEarnings,
    required this.monthEarnings,
    required this.completedCount,
    required this.onWithdraw,
  });

  final double totalEarnings;
  final double monthEarnings;
  final int completedCount;
  final VoidCallback onWithdraw;

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
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Earnings Wallet',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Payouts, completed trips, and monthly earnings',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFCCFBF1)),
                ),
                child: const Text(
                  'Live',
                  style: TextStyle(
                    color: Color(0xFF0F766E),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Available balance',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            alignment: Alignment.centerLeft,
            child: Text(
              'NGN ${totalEarnings.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 34,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _WalletMetric(
                  label: 'This month',
                  value: 'NGN ${monthEarnings.toStringAsFixed(0)}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WalletMetric(
                  label: 'Completed',
                  value: '$completedCount',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onWithdraw,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.call_made_rounded),
              label: const Text('Withdraw to Bank Account'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletMetric extends StatelessWidget {
  const _WalletMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutStep extends StatelessWidget {
  const _PayoutStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0F766E)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(color: Color(0xFF64748B), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningsSkeleton extends StatelessWidget {
  const _EarningsSkeleton();

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
                'Loading earnings wallet',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
