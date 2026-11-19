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
    0 => 'EFATA',
    1 => 'Send Goods',
    2 => 'Orders',
    _ => 'EFATA',
  };

  Widget dashboardTab() {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              Text(
                'Send a delivery',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              CustomerPrimaryAction(
                onPressed: () => setState(() => currentIndex = 1),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Schedule pickup'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const SimpleOrderForm(scheduleOnOpen: true),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ActiveDeliverySection(
                onOpenOrders: () => setState(() => currentIndex = 2),
              ),
              const SizedBox(height: 20),
              const CustomerSummaryCard(),
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
      appBar: currentIndex == 3
          ? null
          : AppBar(title: Text(title), automaticallyImplyLeading: false),
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
          const SafeArea(
            bottom: false,
            child: CustomerProfileScreen(embedded: true),
          ),
        ],
      ),
    );
  }
}
