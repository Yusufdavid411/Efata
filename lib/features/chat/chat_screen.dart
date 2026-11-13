import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/config/efata_backend_config.dart';
import '../../core/models/efata_api_models.dart';
import '../../core/services/app_notification_banner_service.dart';
import '../../core/services/efata_api_client.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.orderId,
    required this.participantRole,
  });

  final String orderId;
  final String participantRole;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController controller = TextEditingController();
  bool isSending = false;
  Timer? _apiTimer;
  List<EfataMessage> _apiMessages = const [];
  EfataOrder? _apiOrder;
  Object? _apiError;
  bool _apiLoading = false;
  String? _lastMarkedMessageId;

  CollectionReference<Map<String, dynamic>> get messagesRef => FirebaseFirestore
      .instance
      .collection('orders')
      .doc(widget.orderId)
      .collection('messages');

  String get unreadField => widget.participantRole == 'driver'
      ? 'unreadForDriver'
      : 'unreadForCustomer';

  String get recipientUnreadField => widget.participantRole == 'driver'
      ? 'unreadForCustomer'
      : 'unreadForDriver';

  String get readAtField => widget.participantRole == 'driver'
      ? 'driverLastReadAt'
      : 'customerLastReadAt';

  @override
  void initState() {
    super.initState();
    if (EfataBackendConfig.useNewBackend) {
      _refreshApiChat();
      _apiTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refreshApiChat(),
      );
    } else {
      markChatRead();
    }
  }

  @override
  void dispose() {
    _apiTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> markChatRead() async {
    if (EfataBackendConfig.useNewBackend) {
      await EfataApiClient.instance.markMessagesRead(widget.orderId);
      return;
    }
    await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .set({
          unreadField: 0,
          readAtField: FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .catchError((_) {});
  }

  Future<void> sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    final text = controller.text.trim();

    if (user == null || text.isEmpty || isSending) return;

    if (EfataBackendConfig.useNewBackend) {
      await _sendApiMessage(text);
      return;
    }

    setState(() => isSending = true);

    try {
      final order = await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .get();
      final orderData = order.data();

      if (_isClosedOrder(orderData)) {
        if (!mounted) return;
        AppNotificationBannerService.error(
          'This delivery has ended, so the chat is now closed.',
          title: 'Chat closed',
        );
        setState(() => isSending = false);
        return;
      }

      controller.clear();

      await messagesRef.add({
        'text': text,
        'senderId': user.uid,
        'senderName': user.displayName ?? user.email ?? widget.participantRole,
        'senderRole': widget.participantRole,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        'Message failed: $e',
        title: 'Message not sent',
      );
      if (mounted) {
        setState(() => isSending = false);
      }
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .set({
            'lastMessage': text,
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastMessageSenderId': user.uid,
            'lastMessageSenderRole': widget.participantRole,
            recipientUnreadField: FieldValue.increment(1),
            unreadField: 0,
            readAtField: FieldValue.serverTimestamp(),
            'notificationStatus': 'chatMessage',
          }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        'Message sent, but alert failed: $e',
        title: 'Alert not sent',
      );
    } finally {
      if (mounted) {
        setState(() => isSending = false);
      }
    }
  }

  Future<void> _sendApiMessage(String text) async {
    setState(() => isSending = true);
    try {
      final message = await EfataApiClient.instance.sendMessage(
        widget.orderId,
        text,
      );
      controller.clear();
      if (!mounted) return;
      setState(() {
        _apiMessages = [..._apiMessages, message];
        _apiError = null;
      });
    } on EfataApiException catch (error) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        error.code == 'chat_closed'
            ? 'This delivery has ended, so the chat is now closed.'
            : 'Your message could not be sent. Please try again.',
        title: error.code == 'chat_closed' ? 'Chat closed' : 'Message not sent',
      );
      if (error.code == 'chat_closed') await _refreshApiChat();
    } catch (_) {
      if (!mounted) return;
      AppNotificationBannerService.error(
        'Your message could not be sent. Please try again.',
        title: 'Message not sent',
      );
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  Future<void> _refreshApiChat() async {
    if (_apiLoading) return;
    _apiLoading = true;
    try {
      final results = await Future.wait<Object>([
        EfataApiClient.instance.getOrder(widget.orderId),
        EfataApiClient.instance.listMessages(widget.orderId),
      ]);
      final order = results[0] as EfataOrder;
      final messages = (results[1] as EfataMessagePage).messages;
      final newestId = messages.isEmpty ? null : messages.last.id;
      if (newestId != null && newestId != _lastMarkedMessageId) {
        await EfataApiClient.instance.markMessagesRead(widget.orderId);
        _lastMarkedMessageId = newestId;
      }
      if (!mounted) return;
      setState(() {
        _apiOrder = order;
        _apiMessages = messages;
        _apiError = null;
      });
      if (_isClosedStatus(order.status)) _apiTimer?.cancel();
    } catch (error) {
      if (!mounted) return;
      setState(() => _apiError = error);
    } finally {
      _apiLoading = false;
    }
  }

  String formatTime(dynamic value) {
    if (value is! Timestamp) return '';

    final date = value.toDate();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  bool _isClosedOrder(Map<String, dynamic>? data) {
    if (data == null || data['chatClosedAt'] != null) return true;

    final status = data['status']?.toString().toLowerCase().replaceAll(
      RegExp(r'[\s_-]+'),
      '',
    );

    return status == 'completed' ||
        status == 'canceled' ||
        status == 'cancelled' ||
        status == 'rejected';
  }

  bool _isClosedStatus(String status) {
    final normalized = status.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    return normalized == 'completed' ||
        normalized == 'canceled' ||
        normalized == 'cancelled' ||
        normalized == 'rejected';
  }

  @override
  Widget build(BuildContext context) {
    if (EfataBackendConfig.useNewBackend) return _buildApiChat(context);
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Chat'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: messagesRef
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return const Center(child: Text('Chat could not load'));
                }

                final messages = snapshot.data?.docs ?? [];

                if (messages.isNotEmpty) {
                  markChatRead();
                }

                if (messages.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No messages yet. Start the delivery conversation here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data();
                    final isMine = data['senderId'] == currentUser?.uid;

                    return Align(
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78,
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: isMine
                                ? const Color(0xFF0F766E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isMine
                                  ? const Color(0xFF0F766E)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['text']?.toString() ?? '',
                                style: TextStyle(
                                  color: isMine
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  data['senderRole']?.toString() ?? 'user',
                                  formatTime(data['createdAt']),
                                ].where((item) => item.isNotEmpty).join(' - '),
                                style: TextStyle(
                                  color: isMine
                                      ? Colors.white70
                                      : const Color(0xFF64748B),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Message about this delivery',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: isSending ? null : sendMessage,
                    icon: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiChat(BuildContext context) {
    final order = _apiOrder;
    final isClosed = order != null && _isClosedStatus(order.status);
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Chat'), centerTitle: true),
      body: Column(
        children: [
          if (isClosed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFF1F5F9),
              child: const Text(
                'This delivery has ended. The conversation is read-only.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          Expanded(child: _buildApiMessages()),
          if (!isClosed) _buildApiComposer(),
        ],
      ),
    );
  }

  Widget _buildApiMessages() {
    if (_apiOrder == null && _apiError == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_apiOrder == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _refreshApiChat,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reload chat'),
        ),
      );
    }
    if (_apiMessages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No messages yet. Start the delivery conversation here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshApiChat,
      child: ListView.builder(
        reverse: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        itemCount: _apiMessages.length,
        itemBuilder: (context, reversedIndex) {
          final index = _apiMessages.length - reversedIndex - 1;
          final message = _apiMessages[index];
          final isMine = message.senderRole == widget.participantRole;
          return _ApiMessageBubble(message: message, isMine: isMine);
        },
      ),
    );
  }

  Widget _buildApiComposer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Message about this delivery',
                  prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: isSending ? null : sendMessage,
              icon: isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiMessageBubble extends StatelessWidget {
  const _ApiMessageBubble({required this.message, required this.isMine});

  final EfataMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final createdAt = message.createdAt;
    final time = createdAt == null
        ? ''
        : '${createdAt.toLocal().hour.toString().padLeft(2, '0')}:${createdAt.toLocal().minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isMine ? const Color(0xFF0F766E) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isMine ? const Color(0xFF0F766E) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.body,
                style: TextStyle(
                  color: isMine ? Colors.white : const Color(0xFF0F172A),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  message.senderRole,
                  time,
                ].where((item) => item.isNotEmpty).join(' - '),
                style: TextStyle(
                  color: isMine ? Colors.white70 : const Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
