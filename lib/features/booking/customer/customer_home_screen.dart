import 'package:flutter/material.dart';
import '../../../shared/widgets/app_bottom_navigation.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../../shared/widgets/ai_floating_button.dart';
import 'widgets/customer_summary_card.dart';
import 'widgets/customer_primary_action.dart';
import 'widgets/active_delivery_section.dart';
import 'simple_order_form.dart';

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(isDriver: false),
      appBar: AppBar(
        title: const Text("Customer Dashboard"),
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavigation(
        isDriver: false,
        currentIndex: 0,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
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
              ],
            ),
          ),
          const AIFloatingButton(),
        ],
      ),
    );
  }
}
