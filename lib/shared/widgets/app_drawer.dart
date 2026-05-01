import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppDrawer extends StatelessWidget {
  final bool isDriver;

  const AppDrawer({super.key, required this.isDriver});

  void openProfile(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      isDriver ? '/driverProfile' : '/customerProfile',
    );
  }

  Future<String> getDisplayName(User? user) async {
    if (user == null) return "User";

    if (isDriver) {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .get();

      final data = doc.data();
      final name = data?['fullName']?.toString();

      if (name != null && name.trim().isNotEmpty) {
        return name;
      }
    }

    final authName = user.displayName;
    if (authName != null && authName.trim().isNotEmpty) {
      return authName;
    }

    return isDriver ? "Driver" : "Customer";
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Drawer(
      child: Column(
        children: [
          FutureBuilder<String>(
            future: getDisplayName(user),
            builder: (context, snapshot) {
              final name = snapshot.data ?? "User";

              return GestureDetector(
                onTap: () => openProfile(context),
                child: UserAccountsDrawerHeader(
                  accountName: Text(name),
                  accountEmail: const Text("Tap to view profile"),
                  currentAccountPicture: const CircleAvatar(
                    child: Icon(Icons.person, size: 30),
                  ),
                ),
              );
            },
          ),

          if (!isDriver)
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text("Create Transport Request"),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/createOrder');
              },
            ),

          if (!isDriver)
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text("My Orders"),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/orders');
              },
            ),

          if (isDriver)
            ListTile(
              leading: const Icon(Icons.work_history),
              title: const Text("Job History"),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/driverJobs');
              },
            ),

          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text("Settings"),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
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