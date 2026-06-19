import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AvailableJobsSection extends StatefulWidget {
  final bool isOnline;

  const AvailableJobsSection({super.key, required this.isOnline});

  @override
  State<AvailableJobsSection> createState() => _AvailableJobsSectionState();
}

class _AvailableJobsSectionState extends State<AvailableJobsSection> {
  List<QueryDocumentSnapshot> _cachedJobs = [];
  bool _isApprovedDriver(Map<String, dynamic>? data) {
    return data?['profileCompleted'] == true &&
        data?['verificationStatus']?.toString().toLowerCase() == 'approved';
  }

  String formatPrice(dynamic price) {
    if (price == null) return "Price not available";

    if (price is num) {
      return "NGN ${price.toStringAsFixed(0)}";
    }

    final parsed = double.tryParse(price.toString());
    if (parsed != null) {
      return "NGN ${parsed.toStringAsFixed(0)}";
    }

    return "Price not available";
  }

  Future<void> acceptJob(String orderId, String driverId) async {
    final driverProfile = await FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .get();

    if (!_isApprovedDriver(driverProfile.data())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Admin approval is required before accepting jobs"),
        ),
      );
      return;
    }

    final activeJobs = await FirebaseFirestore.instance
        .collection('orders')
        .where('driverId', isEqualTo: driverId)
        .get();

    final hasActive = activeJobs.docs.any((doc) {
      final status = doc['status'];
      return status == 'accepted' || status == 'inTransit';
    });

    if (!mounted) return;

    if (hasActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Complete your current job first")),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      'driverId': driverId,
      'status': 'accepted',
      'acceptedAt': Timestamp.now(),
    });
  }

  Future<void> hideJobForDriver(String orderId, String driverId) async {
    await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      'rejectedBy': FieldValue.arrayUnion([driverId]),
    });
  }

  List<QueryDocumentSnapshot> _prepareJobs(
    List<QueryDocumentSnapshot> docs,
    String driverId,
  ) {
    final filtered = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      final status = data['status']?.toString() ?? '';
      final rejectedByRaw = data['rejectedBy'];
      final rejectedBy = rejectedByRaw is List ? rejectedByRaw : [];

      return status == 'pending' && !rejectedBy.contains(driverId);
    }).toList();

    filtered.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;

      final aTime =
          (aData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final bTime =
          (bData['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

      return bTime.compareTo(aTime); // newest first
    });

    return filtered;
  }

  Widget _buildOfflineNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "You are offline. You can still view already loaded jobs, but you will not receive the latest available jobs until you go online again.",
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(
    BuildContext context,
    QueryDocumentSnapshot job,
    String driverId,
  ) {
    final data = job.data() as Map<String, dynamic>;

    final pickup = data['pickup']?.toString() ?? 'No pickup location';
    final dropoff = data['dropoff']?.toString() ?? 'No drop-off location';
    final item = data['item']?.toString() ?? 'No item description';
    final vehicleType = data['vehicleType']?.toString();
    final price = data['price'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "$pickup -> $dropoff",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text("Item: $item"),
            if (vehicleType != null && vehicleType.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text("Vehicle: $vehicleType"),
            ],
            const SizedBox(height: 8),
            Text(
              formatPrice(price),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await acceptJob(job.id, driverId);
                    },
                    child: const Text("Accept"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await hideJobForDriver(job.id, driverId);
                    },
                    child: const Text("Reject"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobList(BuildContext context, String driverId) {
    if (_cachedJobs.isEmpty) {
      return const Text("No available jobs");
    }

    return Column(
      children: _cachedJobs.map((job) {
        return _buildJobCard(context, job, driverId);
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driver = FirebaseAuth.instance.currentUser;

    if (driver == null) {
      return const Text("Driver not logged in");
    }

    if (!widget.isOnline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildOfflineNotice(), _buildJobList(context, driver.uid)],
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('drivers')
          .doc(driver.uid)
          .snapshots(),
      builder: (context, driverSnapshot) {
        final driverData = driverSnapshot.data?.data() as Map<String, dynamic>?;

        if (driverSnapshot.hasData && !_isApprovedDriver(driverData)) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Text(
              "Jobs will appear here after your driver account is approved.",
            ),
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                _cachedJobs.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Text("Something went wrong: ${snapshot.error}");
            }

            if (snapshot.hasData) {
              _cachedJobs = _prepareJobs(snapshot.data!.docs, driver.uid);
            }

            return _buildJobList(context, driver.uid);
          },
        );
      },
    );
  }
}
