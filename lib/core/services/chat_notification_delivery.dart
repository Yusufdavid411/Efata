/// Serializes delivery checks and reserves each message before displaying it.
class ChatNotificationDelivery {
  ChatNotificationDelivery({
    required this.readLocal,
    required this.saveLocal,
    required this.claimRemote,
  });

  final Future<int> Function(String userId, String orderId) readLocal;
  final Future<void> Function(String userId, String orderId, int time)
  saveLocal;
  final Future<bool> Function(String userId, String orderId, int time)
  claimRemote;
  Future<void> _pending = Future<void>.value();

  Future<void> deliver({
    required String userId,
    required String orderId,
    required int messageTime,
    required bool Function() isCurrentSession,
    required Future<void> Function() show,
  }) {
    final result = _pending.then((_) async {
      if (!isCurrentSession()) return;
      final localTime = await readLocal(userId, orderId);
      if (!isCurrentSession()) return;

      // Import existing phone receipts so another phone cannot replay them.
      final claimed = await claimRemote(
        userId,
        orderId,
        localTime > messageTime ? localTime : messageTime,
      );
      if (!isCurrentSession()) return;
      if (messageTime > localTime) {
        await saveLocal(userId, orderId, messageTime);
      }
      if (claimed && messageTime > localTime && isCurrentSession()) {
        await show();
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static bool isEligible({
    required DateTime now,
    required int messageTime,
    required bool isClosed,
    int? closedTime,
  }) {
    final age = now.millisecondsSinceEpoch - messageTime;
    // Historic unread messages remain in chat, but must not become new alerts.
    if (age > const Duration(hours: 24).inMilliseconds || age < -60000) {
      return false;
    }
    if (isClosed && (closedTime == null || messageTime > closedTime)) {
      return false;
    }
    return true;
  }
}
