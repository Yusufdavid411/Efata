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
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = screenWidth < 430 ? screenWidth * 0.78 : 340.0;

    return Drawer(
      width: drawerWidth,
      child: Column(
        children: [
          if (user == null)
            const _DrawerProfileHeader(name: 'EFATA', role: 'Account')
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
                    : isDriver && user.displayName?.trim().isNotEmpty == true
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
                    : null;

                return _DrawerProfileHeader(
                  name: name,
                  role: isDriver ? 'Driver account' : 'Customer account',
                  status: status,
                  statusOk: isDriver ? verificationStatus == 'approved' : true,
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
                  subtitle: isDriver
                      ? 'Account details and approval status'
                      : 'Account details',
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
                  subtitle: 'Account protection and delivery support',
                ),
              ],
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
    required this.role,
    this.status,
    this.statusOk = false,
    this.photoUrl,
    this.onTap,
  });

  final String name;
  final String role;
  final String? status;
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
          18,
          MediaQuery.of(context).padding.top + 18,
          14,
          18,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFFEFFAF7),
                  backgroundImage:
                      photoUrl != null && photoUrl!.trim().isNotEmpty
                      ? NetworkImage(photoUrl!)
                      : null,
                  child: photoUrl == null || photoUrl!.trim().isEmpty
                      ? const Icon(
                          Icons.person_rounded,
                          color: Color(0xFF0F766E),
                          size: 36,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _HeaderPill(label: role),
                          if (status != null)
                            _HeaderPill(
                              label: status!,
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF475569),
                  ),
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
        color: highlighted ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: highlighted
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF475569),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: highlighted
                  ? const Color(0xFF166534)
                  : const Color(0xFF475569),
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
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF0F766E);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
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
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
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
                    color: const Color(0xFF94A3B8),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
