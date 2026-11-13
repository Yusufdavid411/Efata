import 'dart:async';

import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _refreshApiChat();
    _apiTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshApiChat(),
    );
  }

  @override
  void dispose() {
    _apiTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> sendMessage() async {
    final text = controller.text.trim();
    if (text.isNotEmpty && !isSending) await _sendApiMessage(text);
  }

  Future<void> _sendApiMessage(String text) async {
    setState(() => isSending = true);
    try {
      final message = await EfataApiClient.instance.sendMessage(
        widget.orderId,
        text,
      );
      if (!mounted) return;
      if (controller.text.trim() == text) controller.clear();
      setState(() {
        if (!_apiMessages.any((entry) => entry.id == message.id)) {
          _apiMessages = [..._apiMessages, message];
        }
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

  bool _isClosedStatus(String status) {
    final normalized = status.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    return normalized == 'completed' ||
        normalized == 'canceled' ||
        normalized == 'cancelled' ||
        normalized == 'rejected';
  }

  @override
  Widget build(BuildContext context) => _buildApiChat(context);

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
