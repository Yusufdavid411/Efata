import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/core/services/chat_notification_delivery.dart';

void main() {
  late Map<String, int> local;
  late Map<String, int> remote;
  late int shown;

  ChatNotificationDelivery delivery() => ChatNotificationDelivery(
    readLocal: (user, order) async => local['$user/$order'] ?? 0,
    saveLocal: (user, order, time) async {
      local['$user/$order'] = time;
    },
    claimRemote: (user, order, time) async {
      final key = '$user/$order';
      if ((remote[key] ?? 0) >= time) return false;
      remote[key] = time;
      return true;
    },
  );

  Future<void> send(
    ChatNotificationDelivery target, {
    String user = 'passenger',
    int time = 100,
    bool Function()? isCurrentSession,
    Future<void> Function()? show,
  }) => target.deliver(
    userId: user,
    orderId: 'order',
    messageTime: time,
    isCurrentSession: isCurrentSession ?? () => true,
    show:
        show ??
        () async {
          shown++;
        },
  );

  setUp(() {
    local = {};
    remote = {};
    shown = 0;
  });

  test('overlapping snapshots display one alert', () async {
    final target = delivery();
    await Future.wait(List.generate(6, (_) => send(target)));
    expect(shown, 1);
  });

  test(
    'logout, login and a new phone do not replay a delivered message',
    () async {
      await send(delivery());
      await send(delivery());
      local = {};
      await send(delivery());
      expect(shown, 1);
    },
  );

  test('a newer message and a different recipient can notify', () async {
    final target = delivery();
    await send(target);
    await send(target, time: 101);
    await send(target, user: 'driver', time: 101);
    expect(shown, 3);
  });

  test('legacy local receipt is imported for a new phone', () async {
    local['passenger/order'] = 100;
    await send(delivery());
    local = {};
    await send(delivery());
    expect(shown, 0);
    expect(remote['passenger/order'], 100);
  });

  test('stale authentication callbacks cannot display alerts', () async {
    await send(delivery(), isCurrentSession: () => false);
    expect(shown, 0);
    expect(remote, isEmpty);
  });

  test('a display failure does not replay on the next login', () async {
    await expectLater(
      send(
        delivery(),
        show: () async {
          throw StateError('notification failure');
        },
      ),
      throwsStateError,
    );
    await send(delivery());
    expect(shown, 0);
  });

  test('historic messages cannot reappear as new alerts', () {
    final now = DateTime.utc(2026, 11, 1);
    expect(
      ChatNotificationDelivery.isEligible(
        now: now,
        messageTime: now
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch,
        isClosed: true,
        closedTime: now
            .subtract(const Duration(days: 29))
            .millisecondsSinceEpoch,
      ),
      isFalse,
    );
  });

  test('a recent message sent before closure remains eligible once', () {
    final now = DateTime.utc(2026, 11, 1);
    final before = now
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    expect(
      ChatNotificationDelivery.isEligible(
        now: now,
        messageTime: before,
        isClosed: true,
        closedTime: before + 1000,
      ),
      isTrue,
    );
    expect(
      ChatNotificationDelivery.isEligible(
        now: now,
        messageTime: before,
        isClosed: true,
        closedTime: before - 1000,
      ),
      isFalse,
    );
  });
}
