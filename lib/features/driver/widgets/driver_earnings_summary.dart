import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DriverEarningsSummary extends StatelessWidget {
  const DriverEarningsSummary({super.key});

  double _parsePrice(dynamic price) {
    if (price is num) return price.toDouble();
    return double.tryParse(price?.toString() ?? '') ?? 0;
  }

  bool _isThisMonth(Timestamp? timestamp) {
    if (timestamp == null) return false;
    final date = timestamp.toDate();
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

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
    final driver = FirebaseAuth.instance.currentUser;
    if (driver == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: driver.uid)
          .where('status', isEqualTo: 'completed')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _EarningsSkeleton();
        }

        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text('Earnings could not load: ${snapshot.error}'),
            ),
          );
        }

        final jobs = snapshot.data?.docs ?? [];
        double totalEarnings = 0;
        double monthEarnings = 0;

        for (final job in jobs) {
          final data = job.data() as Map<String, dynamic>;
          final price = _parsePrice(data['price']);
          totalEarnings += price;
          if (_isThisMonth(data['completedAt'] as Timestamp?)) {
            monthEarnings += price;
          }
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF115E59)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F766E),
                blurRadius: 26,
                offset: Offset(0, 14),
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
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Colors.white,
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
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Ready for payout',
                          style: TextStyle(color: Color(0xFFCCFBF1)),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
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
                style: TextStyle(color: Color(0xFFCCFBF1)),
              ),
              const SizedBox(height: 4),
              FittedBox(
                alignment: Alignment.centerLeft,
                child: Text(
                  'NGN ${totalEarnings.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
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
                      value: '${jobs.length}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      showWithdrawalProcess(context, totalEarnings),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F766E),
                  ),
                  icon: const Icon(Icons.call_made_rounded),
                  label: const Text('Withdraw to Bank Account'),
                ),
              ),
            ],
          ),
        );
      },
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
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFCCFBF1))),
          const SizedBox(height: 4),
          FittedBox(
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
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
