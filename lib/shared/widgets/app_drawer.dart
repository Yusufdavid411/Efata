import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../features/driver/driver_profile_screen.dart';

class AppDrawer extends StatelessWidget {
  final bool isDriver;

  const AppDrawer({super.key, this.isDriver = false});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // 🔥 CLICKABLE HEADER
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DriverProfileScreen(),
                ),
              );
            },
            child: UserAccountsDrawerHeader(
              accountName: Text(user?.displayName ?? "User"),
              accountEmail: Text(user?.email ?? ""),
              currentAccountPicture: const CircleAvatar(
                child: Icon(Icons.person),
              ),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text("Dashboard"),
            onTap: () => Navigator.pop(context),
          ),

          ListTile(
            leading: const Icon(Icons.local_shipping),
            title: const Text("Active Jobs"),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/driverActiveJobs');
            },
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text("Logout"),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/',
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}