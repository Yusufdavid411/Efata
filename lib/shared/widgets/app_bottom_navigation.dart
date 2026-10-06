import 'package:flutter/material.dart';

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.isDriver,
    required this.currentIndex,
  });

  final bool isDriver;
  final int currentIndex;

  void _open(BuildContext context, int index) {
    if (index == currentIndex) return;

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

    Navigator.pushNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      height: 70,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      indicatorColor: const Color(0xFFE0F2F1),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (index) => _open(context, index),
      destinations: isDriver
          ? const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: 'Home',
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
                label: 'Home',
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
    );
  }
}
