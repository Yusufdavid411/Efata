import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/app_settings_controller.dart';
import 'app_notification_banner_service.dart';
import 'efata_api_client.dart';
import 'efata_session.dart';

class ChatNotificationService {
  ChatNotificationService._();

  static final ChatNotificationService instance = ChatNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Timer? _poller;
  bool _polling = false;

  Future<void> initialize() async {
    if (_poller != null) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(settings: initializationSettings);

    await requestPhonePermission();

    _poller = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }

  Future<void> _poll() async {
    final uid = EfataSession.instance.accountUid;
    if (uid == null || _polling ||
        !appSettingsController.orderNotificationsEnabled) return;
    _polling = true;
    try {
      final api = EfataApiClient.instance;
      final account = await api.getMe();
      final page = await api.listOrders();
      final prefs = await SharedPreferences.getInstance();
      for (final order in page.orders) {
        if (EfataSession.instance.accountUid != uid) return;
        if (!['pending', 'accepted', 'inTransit'].contains(order.status)) continue;
        final unread = account.role == 'driver'
            ? order.unreadForDriver : order.unreadForCustomer;
        final time = order.lastMessageAt?.millisecondsSinceEpoch;
        final message = order.lastMessage;
        if (unread < 1 || time == null || message == null || message.isEmpty) continue;
        final key = 'efata-chat-delivered:$uid:${order.id}';
        if (time <= (prefs.getInt(key) ?? 0)) continue;
        await prefs.setInt(key, time);
        if (EfataSession.instance.accountUid != uid) return;
        await showChatNotification(orderId: order.id,
          title: account.role == 'driver' ? 'Customer' : 'Driver', body: message);
      }
    } catch (_) {
      // Retry on the next poll without interrupting the current screen.
    } finally {
      _polling = false;
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

  Future<void> dispose() async {
    _poller?.cancel();
    _poller = null;
  }
}
