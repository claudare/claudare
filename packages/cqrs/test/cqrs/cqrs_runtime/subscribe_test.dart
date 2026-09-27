import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  test('filters event changes without deduplicating stream paths', () async {
    final store = MemoryEventStore();
    final runtime = CqrsTestRuntime(eventStore: store);
    var exact = 0;
    var prefix = 0;
    var all = 0;
    final exactSubscription = runtime
        .subscribe(const PatternFilter.exact('notes/one'))
        .listen((_) => exact++);
    final prefixSubscription = runtime
        .subscribe(const PatternFilter.startsWith('notes/'))
        .listen((_) => prefix++);
    final allSubscription = runtime
        .subscribe(const PatternFilter.all())
        .listen((_) => all++);
    addTearDown(exactSubscription.cancel);
    addTearDown(prefixSubscription.cancel);
    addTearDown(allSubscription.cancel);
    final time = DateTime.utc(2026);

    expect(
      await store.addStoredCommand(
        StoredCommand(
          commandId: const CommandId('actor', 1),
          dependency: CommandDependency(),
          occuredAt: time,
          events: [
            for (final path in ['other', 'notes/one', 'notes/one', 'notes/two'])
              StoredCommandEvent(
                streamPath: path,
                encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
                occuredAt: time,
              ),
          ],
        ),
      ),
      isTrue,
    );

    await Future<void>.delayed(Duration.zero);

    expect(exact, 2);
    expect(prefix, 3);
    expect(all, 4);
  });
}
