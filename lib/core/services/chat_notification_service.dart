import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../controllers/app_settings_controller.dart';

class ChatNotificationService {
  ChatNotificationService._();

  static final ChatNotificationService instance = ChatNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final Map<String, int> _seenMessageTimes = {};
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _orderSubscriptions = [];

  StreamSubscription<User?>? _authSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(settings: initializationSettings);

    await requestPhonePermission();

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _clearOrderListeners();

      if (user != null) {
        _listenForOrderMessages(user.uid);
      }
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _listenForOrderMessages(user.uid);
    }

    _initialized = true;
  }

  void _listenForOrderMessages(String userId) {
    _orderSubscriptions.add(
      FirebaseFirestore.instance
          .collection('orders')
          .where('customerId', isEqualTo: userId)
          .snapshots()
          .listen((snapshot) => _handleOrderSnapshot(snapshot, userId)),
    );

    _orderSubscriptions.add(
      FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: userId)
          .snapshots()
          .listen((snapshot) => _handleOrderSnapshot(snapshot, userId)),
    );
  }

  void _handleOrderSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    String userId,
  ) {
    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.removed) continue;

      final order = change.doc;
      final data = order.data();
      if (data == null) continue;

      final lastMessage = data['lastMessage']?.toString() ?? '';
      final senderId = data['lastMessageSenderId']?.toString();
      final lastMessageAt = data['lastMessageAt'];
      final messageTime = _messageTime(lastMessageAt);
      final unreadCount = _unreadCountForUser(data, userId);

      if (lastMessage.isEmpty || senderId == null || messageTime == null) {
        continue;
      }

      final previousTime = _seenMessageTimes[order.id];
      _seenMessageTimes[order.id] = messageTime;

      final isInitialLoad = previousTime == null;
      final isOwnMessage = senderId == userId;

      if (isOwnMessage) continue;
      if (isInitialLoad && unreadCount <= 0) continue;
      if (!isInitialLoad && messageTime <= previousTime) continue;
      if (!appSettingsController.orderNotificationsEnabled) continue;

      showChatNotification(
        orderId: order.id,
        title: _senderTitle(data['lastMessageSenderRole']),
        body: lastMessage,
      );
    }
  }

  int? _messageTime(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is int) return value;
    return null;
  }

  int _unreadCountForUser(Map<String, dynamic> data, String userId) {
    final isCustomer = data['customerId']?.toString() == userId;
    final field = isCustomer ? 'unreadForCustomer' : 'unreadForDriver';

    return (data[field] as num?)?.toInt() ?? 0;
  }

  String _senderTitle(dynamic senderRole) {
    switch (senderRole?.toString().toLowerCase()) {
      case 'customer':
        return 'Customer';
      case 'driver':
        return 'Driver';
      default:
        return 'Delivery chat';
    }
  }

  Future<void> showChatNotification({
    required String orderId,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'delivery_chat_messages',
      'Delivery chat messages',
      channelDescription: 'Notifications for new delivery chat messages',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
    );

    await _notifications.show(
      id: orderId.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: orderId,
    );
  }

  Future<bool?> requestPhonePermission() async {
    return await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> showTestNotification() {
    return showChatNotification(
      orderId: 'test-chat-notification',
      title: 'EFATA chat notification',
      body: 'Notifications are working on this phone.',
    );
  }

  void _clearOrderListeners() {
    for (final subscription in _orderSubscriptions) {
      subscription.cancel();
    }
    _orderSubscriptions.clear();
    _seenMessageTimes.clear();
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _clearOrderListeners();
    _initialized = false;
  }
}
