import 'package:flutter/material.dart';

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.isDriver,
    required this.currentIndex,
    this.onDestinationSelected,
  });

  final bool isDriver;
  final int currentIndex;
  final ValueChanged<int>? onDestinationSelected;

  void _open(BuildContext context, int index) {
    if (index == currentIndex) return;
    if (onDestinationSelected != null) {
      onDestinationSelected!(index);
      return;
    }

    final route = isDriver
        ? switch (index) {
            0 => '/driverHome',
            1 => '/driverJobs',
            2 => '/driverProfile',
            _ => '/driverHome',
          }
        : switch (index) {
            0 => '/customerHome',
            1 => '/createOrder',
            2 => '/orders',
            3 => '/customerProfile',
            _ => '/customerHome',
          };

    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        height: 66,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.primaryContainer,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) => _open(context, index),
        destinations: isDriver
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard_rounded),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.work_history_outlined),
                  selectedIcon: Icon(Icons.work_history_rounded),
                  label: 'Jobs',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Profile',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.add_road_outlined),
                  selectedIcon: Icon(Icons.add_road_rounded),
                  label: 'Send',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long_rounded),
                  label: 'Orders',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Profile',
                ),
              ],
      ),
    );
  }
}
