import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  const accountMessage = NotificationBusMessage(
    stream: 'account/1',
    position: 7,
    version: 2,
  );
  const userMessage = NotificationBusMessage(
    stream: 'user/1',
    position: 8,
    version: 1,
  );

  test('delivers to every matching filter in registration order', () {
    final bus = MemoryNotificationBus();
    final received = <String>[];

    bus.listen(const PatternFilter.exact('account/1'), (_) {
      received.add('exact');
    });
    bus.listen(const PatternFilter.startsWith('account/'), (_) {
      received.add('prefix');
    });
    bus.listen(const PatternFilter.exact('account/2'), (_) {
      received.add('other');
    });
    bus.listen(const PatternFilter.any(), (_) {
      received.add('any');
    });

    bus.notify(accountMessage);

    expect(received, ['exact', 'prefix', 'any']);
  });

  test('forwards the notification without changing its fields', () {
    final bus = MemoryNotificationBus();
    NotificationBusMessage? received;
    bus.listen(const PatternFilter.any(), (message) {
      received = message;
    });

    bus.notify(accountMessage);

    expect(received, same(accountMessage));
  });

  test('cancel stops later delivery and is idempotent', () {
    final bus = MemoryNotificationBus();
    var count = 0;
    final subscription = bus.listen(const PatternFilter.any(), (_) {
      count++;
    });

    bus.notify(accountMessage);
    subscription.cancel();
    subscription.cancel();
    bus.notify(userMessage);

    expect(count, 1);
  });

  test('duplicate callbacks can be canceled independently', () {
    final bus = MemoryNotificationBus();
    var count = 0;
    void callback(NotificationBusMessage message) => count++;

    final first = bus.listen(const PatternFilter.any(), callback);
    bus.listen(const PatternFilter.any(), callback);
    first.cancel();

    bus.notify(accountMessage);

    expect(count, 1);
  });

  test('cancellation during delivery skips a pending callback', () {
    final bus = MemoryNotificationBus();
    final received = <String>[];
    late final NotificationBusSubscription pending;
    bus.listen(const PatternFilter.any(), (_) {
      received.add('first');
      pending.cancel();
    });
    pending = bus.listen(const PatternFilter.any(), (_) {
      received.add('pending');
    });

    bus.notify(accountMessage);

    expect(received, ['first']);
  });

  test('a callback added during delivery starts with the next message', () {
    final bus = MemoryNotificationBus();
    final received = <String>[];
    late final NotificationBusSubscription first;
    first = bus.listen(const PatternFilter.any(), (_) {
      received.add('first');
      first.cancel();
      bus.listen(const PatternFilter.any(), (_) {
        received.add('added');
      });
    });

    bus.notify(accountMessage);
    bus.notify(userMessage);

    expect(received, ['first', 'added']);
  });

  for (final failure in <Object>[
    Exception('listener failed'),
    StateError('listener failed'),
  ]) {
    test('a ${failure.runtimeType} does not stop other listeners', () {
      final bus = MemoryNotificationBus();
      final received = <String>[];
      bus.listen(const PatternFilter.any(), (_) {
        throw failure;
      });
      bus.listen(const PatternFilter.any(), (_) {
        received.add('second');
      });

      expect(() => bus.notify(accountMessage), returnsNormally);
      expect(received, ['second']);
    });
  }
}
