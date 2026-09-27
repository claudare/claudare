import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  const accountMessage = 'account/1';
  const userMessage = 'user/1';

  test('stream registers only when listened to and does not replay', () async {
    final bus = _RecordingBus();
    final stream = bus.stream(const PatternFilter.any());
    expect(bus.registrations, 0);
    bus.notify('before-listening');
    final received = <String>[];
    final subscription = stream.listen(received.add);
    addTearDown(subscription.cancel);
    expect(bus.registrations, 1);

    bus.notify(accountMessage);
    await Future<void>.delayed(Duration.zero);

    expect(received, [accountMessage]);
  });

  test('stream delivers matching paths in notification order', () async {
    final bus = MemoryNotificationBus();
    final received = <String>[];
    final subscription = bus
        .stream(const PatternFilter.startsWith('account/'))
        .listen(received.add);
    addTearDown(subscription.cancel);

    bus.notify(accountMessage);
    bus.notify(userMessage);
    bus.notify('account/2');
    await Future<void>.delayed(Duration.zero);

    expect(received, [accountMessage, 'account/2']);
  });

  test('stream cancellation unregisters its bus callback', () async {
    final bus = _RecordingBus();
    final received = <String>[];
    final subscription = bus
        .stream(const PatternFilter.any())
        .listen(received.add);
    bus.notify(accountMessage);
    await Future<void>.delayed(Duration.zero);

    await subscription.cancel();
    await subscription.cancel();
    bus.notify(userMessage);
    await Future<void>.delayed(Duration.zero);

    expect(bus.deliveries, 1);
    expect(received, [accountMessage]);
  });

  test('canceling one stream leaves other subscriptions active', () async {
    final bus = MemoryNotificationBus();
    final first = bus.stream(const PatternFilter.any()).listen((_) {});
    final second = StreamIterator(bus.stream(const PatternFilter.any()));
    addTearDown(second.cancel);
    final next = second.moveNext();

    await first.cancel();
    bus.notify(accountMessage);

    expect(await next, isTrue);
    expect(second.current, accountMessage);
  });

  test(
    'listen stays synchronous alongside asynchronous stream delivery',
    () async {
      final bus = MemoryNotificationBus();
      final received = <String>[];
      final stream = bus
          .stream(const PatternFilter.any())
          .listen((_) => received.add('stream'));
      addTearDown(stream.cancel);
      final callback = bus.listen(
        const PatternFilter.any(),
        (_) => received.add('listen'),
      );
      addTearDown(callback.cancel);

      bus.notify(accountMessage);
      expect(received, ['listen']);
      await Future<void>.delayed(Duration.zero);

      expect(received, ['listen', 'stream']);
    },
  );

  test('each stream allows one listener', () async {
    final bus = _RecordingBus();
    final stream = bus.stream(const PatternFilter.any());
    final subscription = stream.listen((_) {});
    addTearDown(subscription.cancel);

    expect(() => stream.listen((_) {}), throwsStateError);
    expect(bus.registrations, 1);
  });

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

  test('forwards the notified stream path', () {
    final bus = MemoryNotificationBus();
    String? received;
    bus.listen(const PatternFilter.any(), (message) {
      received = message;
    });

    bus.notify(accountMessage);

    expect(received, accountMessage);
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
    void callback(String stream) => count++;

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

class _RecordingBus extends MemoryNotificationBus {
  var registrations = 0;
  var deliveries = 0;

  @override
  NotificationBusSubscription listen(
    PatternFilter filter,
    void Function(String stream) callback,
  ) {
    registrations++;
    return super.listen(filter, (stream) {
      deliveries++;
      callback(stream);
    });
  }
}
