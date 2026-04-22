import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppDrawer extends StatelessWidget {
  final bool isDriver;

  const AppDrawer({super.key, required this.isDriver});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(isDriver ? "Driver" : "Customer"),
            accountEmail: Text(user?.email ?? ""),
            currentAccountPicture: const CircleAvatar(
              child: Icon(Icons.person, size: 30),
            ),
          ),

          if (!isDriver)
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text("Create Transport Request"),
              onTap: () {
                Navigator.pushNamed(context, '/createOrder');
              },
            ),

          if (!isDriver)
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text("My Orders"),
              onTap: () {
                Navigator.pushNamed(context, '/orders');
              },
            ),

          if (isDriver)
            ListTile(
              leading: const Icon(Icons.local_shipping),
              title: const Text("Available Jobs"),
              onTap: () {
                Navigator.pushNamed(context, '/driverHome');
              },
            ),

          if (isDriver)
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text("Job History"),
              onTap: () {
                Navigator.pushNamed(context, '/driverHome');
              },
            ),

          ListTile(
            leading: const Icon(Icons.person),
            title: const Text("Profile"),
            onTap: () {
              Navigator.pushNamed(
                  context, isDriver ? '/driverProfile' : '/customerProfile');
            },
          ),

          const Spacer(),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Logout"),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                  context, '/', (route) => false);
            },
          ),
        ],
      ),
    );
  }
}