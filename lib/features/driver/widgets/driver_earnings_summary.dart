import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverEarningsSummary extends StatelessWidget {
  const DriverEarningsSummary({super.key});

  double _parsePrice(dynamic price) {
    if (price == null) return 0;

    if (price is num) {
      return price.toDouble();
    }

    return double.tryParse(price.toString()) ?? 0;
  }

  void showWithdrawalProcess(BuildContext context, double amount) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Withdraw Earnings"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Available balance: NGN ${amount.toStringAsFixed(0)}"),
            const SizedBox(height: 12),
            const Text(
              "Withdrawal to the driver's bank account will be connected here.",
            ),
            const SizedBox(height: 8),
            const Text("Process:"),
            const SizedBox(height: 4),
            const Text("1. Driver adds bank account details."),
            const Text("2. Admin/payment provider verifies account."),
            const Text("3. Driver requests payout."),
            const Text("4. App records withdrawal status."),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) {
      return const SizedBox();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: driver.uid)
          .where('status', isEqualTo: 'completed')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Text("Something went wrong: ${snapshot.error}");
        }

        final jobs = snapshot.data?.docs ?? [];

        double totalEarnings = 0;
        for (final job in jobs) {
          final data = job.data() as Map<String, dynamic>;
          totalEarnings += _parsePrice(data['price']);
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Earnings Summary",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                "Total Earnings: NGN ${totalEarnings.toStringAsFixed(0)}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Completed Deliveries: ${jobs.length}",
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      showWithdrawalProcess(context, totalEarnings),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text("Withdraw to Bank Account"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
