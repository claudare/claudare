import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  const accountMessage = 'account/1';
  const userMessage = 'user/1';

  test(
    'listening registers the stream without replaying earlier paths',
    () async {
      final bus = MemoryNotificationBus();
      final stream = bus.stream(const PatternFilter.any());
      bus.notify('before-listening');

      final received = <String>[];
      final subscription = stream.listen(received.add);
      addTearDown(subscription.cancel);
      bus.notify(accountMessage);
      await Future<void>.delayed(Duration.zero);

      expect(received, [accountMessage]);
    },
  );

  test('matching paths arrive asynchronously in notification order', () async {
    final bus = MemoryNotificationBus();
    final received = <String>[];
    final subscription = bus
        .stream(const PatternFilter.startsWith('account/'))
        .listen(received.add);
    addTearDown(subscription.cancel);

    bus.notify(accountMessage);
    bus.notify(userMessage);
    bus.notify('account/2');
    expect(received, isEmpty);
    await Future<void>.delayed(Duration.zero);

    expect(received, [accountMessage, 'account/2']);
  });

  test('exact, prefix, and any filters receive matching paths', () async {
    final bus = MemoryNotificationBus();
    final received = <String>[];
    final subscriptions = [
      bus
          .stream(const PatternFilter.exact(accountMessage))
          .listen((_) => received.add('exact')),
      bus
          .stream(const PatternFilter.startsWith('account/'))
          .listen((_) => received.add('prefix')),
      bus
          .stream(const PatternFilter.exact('account/2'))
          .listen((_) => received.add('other')),
      bus.stream(const PatternFilter.any()).listen((_) => received.add('any')),
    ];
    addTearDown(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });

    bus.notify(accountMessage);
    await Future<void>.delayed(Duration.zero);

    expect(received, ['exact', 'prefix', 'any']);
  });

  test('canceling a subscription stops later delivery', () async {
    final bus = MemoryNotificationBus();
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

    expect(received, [accountMessage]);
  });

  test('canceling one stream leaves another active', () async {
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

  test('each stream allows one listener', () async {
    final bus = MemoryNotificationBus();
    final stream = bus.stream(const PatternFilter.any());
    final subscription = stream.listen((_) {});
    addTearDown(subscription.cancel);

    expect(() => stream.listen((_) {}), throwsStateError);
  });
}
