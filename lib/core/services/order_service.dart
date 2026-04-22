import 'package:cloud_firestore/cloud_firestore.dart';

class OrderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> createOrder({
    required String pickup,
    required String dropoff,
    required String item,
    required String customerId,
  }) async {
    await _firestore.collection('orders').add({
      'pickup': pickup,
      'dropoff': dropoff,
      'item': item,
      'customerId': customerId,
      'driverId': null,
      'status': 'pending',
      'createdAt': Timestamp.now(),
    });
  }

  Stream<QuerySnapshot> getPendingOrders() {
    return _firestore
        .collection('orders')
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  Stream<QuerySnapshot> getDriverOrders(String driverId) {
    return _firestore
        .collection('orders')
        .where('driverId', isEqualTo: driverId)
        .snapshots();
  }

  Future<void> acceptOrder(String orderId, String driverId) async {
    await _firestore.collection('orders').doc(orderId).update({
      'status': 'accepted',
      'driverId': driverId,
    });
  }

  Future<void> rejectOrder(String orderId) async {
    await _firestore.collection('orders').doc(orderId).update({
      'status': 'rejected',
    });
  }

  Future<void> startTransit(String orderId) async {
    await _firestore.collection('orders').doc(orderId).update({
      'status': 'inTransit',
    });
  }

  Future<void> completeOrder(String orderId) async {
    await _firestore.collection('orders').doc(orderId).update({
      'status': 'completed',
    });
  }

  Stream<QuerySnapshot> getCustomerOrders(String customerId) {
    return _firestore
        .collection('orders')
        .where('customerId', isEqualTo: customerId)
        .snapshots();
  }
}