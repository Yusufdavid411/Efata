import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
    markChatRead();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> markChatRead() async {
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

    setState(() => isSending = true);

    try {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Message failed: $e')));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message sent, but alert failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => isSending = false);
      }
    }
  }

  String formatTime(dynamic value) {
    if (value is! Timestamp) return '';

    final date = value.toDate();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
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
}
