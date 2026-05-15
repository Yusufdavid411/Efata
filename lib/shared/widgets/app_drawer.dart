import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.isDriver});

  final bool isDriver;

  void openProfile(BuildContext context) {
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      isDriver ? '/driverProfile' : '/customerProfile',
    );
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(User user) {
    return FirebaseFirestore.instance
        .collection(isDriver ? 'drivers' : 'users')
        .doc(user.uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Drawer(
      child: Column(
        children: [
          if (user == null)
            const _DrawerProfileHeader(
              name: 'EFATA',
              email: 'Not signed in',
              role: 'Account',
            )
          else
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: profileStream(user),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() ?? {};
                final name =
                    data['fullName']?.toString().trim().isNotEmpty == true
                    ? data['fullName'].toString()
                    : data['name']?.toString().trim().isNotEmpty == true
                    ? data['name'].toString()
                    : user.displayName?.trim().isNotEmpty == true
                    ? user.displayName!
                    : isDriver
                    ? 'Driver'
                    : 'Customer';
                final photoUrl = data['photoUrl']?.toString();

                return _DrawerProfileHeader(
                  name: name,
                  email: user.email ?? 'No email',
                  role: isDriver ? 'Driver account' : 'Customer account',
                  photoUrl: photoUrl,
                  onTap: () => openProfile(context),
                );
              },
            ),
          if (!isDriver)
            ListTile(
              leading: const Icon(Icons.add_circle_outline_rounded),
              title: const Text('Create Transport Request'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/createOrder');
              },
            ),
          if (!isDriver)
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('My Orders'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/orders');
              },
            ),
          if (isDriver)
            ListTile(
              leading: const Icon(Icons.work_history_outlined),
              title: const Text('Job History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/driverJobs');
              },
            ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
          ),
          const Spacer(),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.red),
              title: const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
          ),
        ],
      ),
    );
  }
}

class _DrawerProfileHeader extends StatelessWidget {
  const _DrawerProfileHeader({
    required this.name,
    required this.email,
    required this.role,
    this.photoUrl,
    this.onTap,
  });

  final String name;
  final String email;
  final String role;
  final String? photoUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.of(context).padding.top + 22,
          20,
          22,
        ),
        decoration: const BoxDecoration(color: Color(0xFF0F172A)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: Colors.white,
              backgroundImage: photoUrl != null && photoUrl!.trim().isNotEmpty
                  ? NetworkImage(photoUrl!)
                  : null,
              child: photoUrl == null || photoUrl!.trim().isEmpty
                  ? const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF0F766E),
                      size: 38,
                    )
                  : null,
            ),
            const SizedBox(height: 14),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFCBD5E1)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                role,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
