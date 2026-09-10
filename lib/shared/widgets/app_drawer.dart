import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';

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

  Future<void> confirmLogout(BuildContext context) async {
    final shouldLogout = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        final body = isDriver
            ? 'You will stop receiving delivery requests after logging out.'
            : 'You will need to sign in again before booking or tracking deliveries.';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Log out of EFATA?',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            body,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Logout'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('Stay Logged In'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldLogout != true) return;

    await AuthService().logout();

    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Drawer(
      width: MediaQuery.of(context).size.width.clamp(300, 380).toDouble(),
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
                final profileCompleted = data['profileCompleted'] == true;
                final verificationStatus = data['verificationStatus']
                    ?.toString()
                    .toLowerCase();
                final status = isDriver
                    ? verificationStatus == 'approved'
                          ? 'Verified driver'
                          : profileCompleted
                          ? 'Approval in review'
                          : 'Profile incomplete'
                    : profileCompleted
                    ? 'Profile ready'
                    : 'Profile incomplete';

                return _DrawerProfileHeader(
                  name: name,
                  email: user.email ?? 'No email',
                  role: isDriver ? 'Driver account' : 'Customer account',
                  status: status,
                  statusOk: isDriver
                      ? verificationStatus == 'approved'
                      : profileCompleted,
                  photoUrl: photoUrl,
                  onTap: () => openProfile(context),
                );
              },
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
              children: [
                _DrawerSectionLabel(
                  label: isDriver ? 'Driver tools' : 'Customer tools',
                ),
                _DrawerTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Profile',
                  subtitle: 'Account details and setup status',
                  onTap: () => openProfile(context),
                ),
                if (!isDriver) ...[
                  _DrawerTile(
                    icon: Icons.add_road_outlined,
                    title: 'Create Transport Request',
                    subtitle: 'Book a new pickup and delivery',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/createOrder');
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.receipt_long_outlined,
                    title: 'My Orders',
                    subtitle: 'Track active and previous deliveries',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/orders');
                    },
                  ),
                ],
                if (isDriver)
                  _DrawerTile(
                    icon: Icons.work_history_outlined,
                    title: 'Job History',
                    subtitle: 'Completed delivery records',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/driverJobs');
                    },
                  ),
                const SizedBox(height: 10),
                const _DrawerSectionLabel(label: 'Support'),
                _DrawerTile(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  subtitle: 'Theme, notifications, and sign-in',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/settings');
                  },
                ),
                _DrawerTile(
                  icon: Icons.support_agent_outlined,
                  title: 'Help & Support',
                  subtitle: isDriver
                      ? 'Get help with jobs, payouts, or verification'
                      : 'Get help with booking, tracking, or payment',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/settings');
                  },
                ),
                const _DrawerTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Trust & Safety',
                  subtitle: 'Verified accounts and delivery protection',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: _DrawerTile(
                icon: Icons.logout_rounded,
                title: 'Logout',
                subtitle: 'Leave this device signed out',
                danger: true,
                onTap: () => confirmLogout(context),
              ),
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
    this.status = 'Account',
    this.statusOk = false,
    this.photoUrl,
    this.onTap,
  });

  final String name;
  final String email;
  final String role;
  final String status;
  final bool statusOk;
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF134E4A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.white,
                  backgroundImage:
                      photoUrl != null && photoUrl!.trim().isNotEmpty
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
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
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
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeaderPill(label: role),
                _HeaderPill(
                  label: status,
                  icon: statusOk
                      ? Icons.verified_rounded
                      : Icons.error_outline_rounded,
                  highlighted: statusOk,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label, this.icon, this.highlighted = false});

  final String label;
  final IconData? icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFFDCFCE7)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: highlighted ? const Color(0xFF16A34A) : Colors.white,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: highlighted ? const Color(0xFF166534) : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFDC2626) : const Color(0xFF0F766E);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: danger ? const Color(0xFFFEF2F2) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: danger ? color : const Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: danger ? color : const Color(0xFF94A3B8),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
