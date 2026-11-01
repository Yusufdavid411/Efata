import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/app_settings_controller.dart';
import 'app_notification_banner_service.dart';
import 'chat_notification_delivery.dart';

class ChatNotificationService {
  ChatNotificationService._();

  static final ChatNotificationService instance = ChatNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  late final ChatNotificationDelivery _delivery = ChatNotificationDelivery(
    readLocal: (userId, orderId) async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_deliveredMessageKey(userId, orderId)) ?? 0;
    },
    saveLocal: (userId, orderId, time) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_deliveredMessageKey(userId, orderId), time);
    },
    claimRemote: _claimNotification,
  );
  int _session = 0;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _orderSubscriptions = [];

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _profileSubscription;
  String? _listeningRole;
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

    _initialized = true;
  }

  void _listenForOrderMessages(String userId) {
    final authSession = _session;
    // Registration can publish the profile after the auth event, so wait for it.
    _profileSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen(
          (profile) {
            if (FirebaseAuth.instance.currentUser?.uid != userId ||
                authSession != _session) {
              return;
            }
            final role = profile.data()?['role']?.toString();
            if (role == _listeningRole) return;
            _listeningRole = role;
            for (final subscription in _orderSubscriptions) {
              subscription.cancel();
            }
            _orderSubscriptions.clear();
            if (role != 'customer' && role != 'driver') return;
            _orderSubscriptions.add(
              FirebaseFirestore.instance
                  .collection('orders')
                  .where(
                    role == 'driver' ? 'driverId' : 'customerId',
                    isEqualTo: userId,
                  )
                  .snapshots()
                  .listen(
                    (snapshot) =>
                        _processSnapshot(snapshot, userId, authSession),
                    onError: (Object error) =>
                        debugPrint('Chat listener: $error'),
                  ),
            );
          },
          onError: (Object error) =>
              debugPrint('Chat profile listener: $error'),
        );
  }

  Future<void> _processSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    String userId,
    int session,
  ) async {
    for (final change in snapshot.docChanges) {
      if (!_isCurrentSession(userId, session)) return;
      if (change.type == DocumentChangeType.removed) continue;

      final order = change.doc;
      final data = order.data();
      if (data == null) continue;

      final lastMessage = data['lastMessage']?.toString() ?? '';
      final senderId = data['lastMessageSenderId']?.toString();
      final lastMessageAt = data['lastMessageAt'];
      final messageTime = _messageTime(lastMessageAt);
      final unreadCount = _unreadCountForUser(data, userId);
      final isClosedOrder = _isClosedOrder(data);

      if (lastMessage.isEmpty || senderId == null || messageTime == null) {
        if (isClosedOrder) {
          await _notifications.cancel(id: _notificationId(order.id));
        }
        continue;
      }

      final isOwnMessage = senderId == userId;
      if (isOwnMessage) continue;
      final closedTime =
          _messageTime(data['chatClosedAt']) ??
          _messageTime(data['completedAt']) ??
          _messageTime(data['canceledAt']) ??
          _messageTime(data['rejectedAt']);
      if (unreadCount <= 0 ||
          !ChatNotificationDelivery.isEligible(
            now: DateTime.now(),
            messageTime: messageTime,
            isClosed: isClosedOrder,
            closedTime: closedTime,
          )) {
        await _notifications.cancel(id: _notificationId(order.id));
        continue;
      }
      if (!appSettingsController.orderNotificationsEnabled) continue;

      try {
        await _delivery.deliver(
          userId: userId,
          orderId: order.id,
          messageTime: messageTime,
          isCurrentSession: () => _isCurrentSession(userId, session),
          show: () => showChatNotification(
            orderId: order.id,
            title: _senderTitle(data['lastMessageSenderRole']),
            body: lastMessage,
          ),
        );
      } catch (error) {
        // Fail closed when a receipt cannot be checked (for example offline).
        debugPrint('Chat notification receipt check failed: $error');
      }
    }
  }

  bool _isCurrentSession(String userId, int session) =>
      session == _session && FirebaseAuth.instance.currentUser?.uid == userId;

  Future<bool> _claimNotification(String userId, String orderId, int time) {
    final receipt = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('chatNotificationReceipts')
        .doc(orderId);
    return FirebaseFirestore.instance.runTransaction((transaction) async {
      final existing = await transaction.get(receipt);
      final delivered = (existing.data()?['messageTime'] as num?)?.toInt() ?? 0;
      if (delivered >= time) return false;
      transaction.set(receipt, {
        'messageTime': time,
        'deliveredAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  String _deliveredMessageKey(String userId, String orderId) {
    return 'efata_chat_notified_${userId}_$orderId';
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
    final cleanTitle = title.trim().isEmpty ? 'Delivery chat' : title.trim();
    final cleanBody = body.trim().isEmpty ? 'You have a new message.' : body;

    AppNotificationBannerService.show(
      title: cleanTitle,
      body: cleanBody,
      icon: Icons.chat_bubble_outline_rounded,
    );

    final androidDetails = AndroidNotificationDetails(
      'delivery_chat_messages',
      'EFATA chat',
      channelDescription:
          'Messages from drivers and customers during active deliveries',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      ticker: 'New EFATA chat message',
      color: Color(0xFF0F766E),
      colorized: true,
      enableVibration: true,
      playSound: true,
      subText: 'Delivery chat',
      styleInformation: BigTextStyleInformation(
        cleanBody,
        contentTitle: cleanTitle,
        summaryText: 'Delivery chat',
      ),
    );

    await _notifications.show(
      id: _notificationId(orderId),
      title: cleanTitle,
      body: cleanBody,
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: orderId,
    );
  }

  int _notificationId(String orderId) => orderId.hashCode & 0x7fffffff;

  bool _isClosedOrder(Map<String, dynamic> data) {
    if (data['chatClosedAt'] != null) return true;

    final status = data['status']?.toString().toLowerCase().replaceAll(
      RegExp(r'[\s_-]+'),
      '',
    );

    return status == 'completed' ||
        status == 'canceled' ||
        status == 'cancelled' ||
        status == 'rejected';
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
    _session++;
    _profileSubscription?.cancel();
    _profileSubscription = null;
    _listeningRole = null;
    for (final subscription in _orderSubscriptions) {
      subscription.cancel();
    }
    _orderSubscriptions.clear();
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _clearOrderListeners();
    _initialized = false;
  }
}
