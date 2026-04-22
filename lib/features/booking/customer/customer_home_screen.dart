import 'package:flutter/material.dart';
import '../../../shared/widgets/app_drawer.dart';
import 'widgets/customer_welcome_header.dart';
import 'widgets/customer_summary_card.dart';
import 'widgets/customer_primary_action.dart';
import 'widgets/active_delivery_section.dart';
import 'widgets/recent_orders_section.dart';
import 'simple_order_form.dart';

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(isDriver: false),
      appBar: AppBar(title: const Text("Customer Dashboard")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const CustomerWelcomeHeader(),
            const SizedBox(height: 20),
            const CustomerSummaryCard(),
            const SizedBox(height: 20),
            CustomerPrimaryAction(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SimpleOrderForm(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const ActiveDeliverySection(),
            const SizedBox(height: 20),
            const Text(
              "Recent Orders",
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const RecentOrdersSection(),
          ],
        ),
      ),
    );
  }
}