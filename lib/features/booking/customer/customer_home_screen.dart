import 'package:flutter/material.dart';
import '../../../shared/widgets/app_bottom_navigation.dart';
import '../../../shared/widgets/ai_floating_button.dart';
import 'widgets/customer_summary_card.dart';
import 'widgets/customer_primary_action.dart';
import 'widgets/active_delivery_section.dart';
import 'simple_order_form.dart';
import 'order_history_screen.dart';
import 'customer_profile_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  int currentIndex = 0;

  String get title => switch (currentIndex) {
    0 => 'Passenger Dashboard',
    1 => 'Send Goods',
    2 => 'Orders',
    3 => 'Profile',
    _ => 'Passenger Dashboard',
  };

  Widget dashboardTab() {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const CustomerSummaryCard(),
              const SizedBox(height: 20),
              CustomerPrimaryAction(
                onPressed: () => setState(() => currentIndex = 1),
              ),
              const SizedBox(height: 20),
              const ActiveDeliverySection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
        const AIFloatingButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: false),
      bottomNavigationBar: AppBottomNavigation(
        isDriver: false,
        currentIndex: currentIndex,
        onDestinationSelected: (index) => setState(() => currentIndex = index),
      ),
      body: IndexedStack(
        index: currentIndex,
        children: [
          dashboardTab(),
          const SimpleOrderForm(embedded: true),
          const OrderHistoryContent(),
          const CustomerProfileScreen(embedded: true),
        ],
      ),
    );
  }
}
