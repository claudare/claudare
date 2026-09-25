import 'dart:typed_data';

import 'package:cqrs/src/cqrs/command/command_dependency.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/memory_event_store.dart';
import 'package:test/test.dart';

void main() {
  group('CqrsRuntime readers', () {
    late EventStore store;
    late CqrsTestRuntime runtime;

    const pageSize = 2;

    setUp(() {
      store = MemoryEventStore(eventFetchPageSize: pageSize);
      runtime = CqrsTestRuntime(eventStore: store);
    });

    test('handles empty result', () async {
      expect(await runtime.streamReader('test').scan().toList(), isEmpty);
    });

    test('handles an empty log', () async {
      expect(await runtime.logReader(0).scan().toList(), isEmpty);
    });

    test('starts stream replay at the supplied version across pages', () async {
      await _appendCount(store, 5);
      final events =
          await runtime.streamReader('test', fromVersion: 1).scan().toList();
      expect(events.map((event) => event.version), [1, 2, 3, 4]);
    });

    test('starts log replay at the supplied position across pages', () async {
      await _appendCount(store, 5);
      final events = await runtime.logReader(1).scan().toList();
      expect(events.map((event) => event.position), [1, 2, 3, 4]);
    });

    test('handles exact page size', () async {
      await _appendCount(store, pageSize);

      final events = await runtime.streamReader('test').scan().toList();
      expect(events, hasLength(pageSize));
      expect(events[0].encodedEvent.kind, 'event-0');
      expect(events[1].encodedEvent.kind, 'event-1');
    });

    test('handles multiple pages', () async {
      await _appendCount(store, pageSize + 1);

      final events = await runtime.streamReader('test').scan().toList();
      expect(events, hasLength(pageSize + 1));
      expect(events.map((event) => event.encodedEvent.kind), [
        'event-0',
        'event-1',
        'event-2',
      ]);
    });
  });
}

Future<void> _appendCount(EventStore store, int count) async {
  for (var i = 0; i < count; i++) {
    await store.saveChanges(
      CommandChanges(
        actor: 'test-actor',
        dependency: CommandDependency(),
        occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        locks: [
          StreamLock(
            streamPath: 'test',
            originatingStreamVersion: i == 0 ? null : i - 1,
          ),
        ],
        events: [
          EventAppend(
            streamPath: 'test',
            encodedEvent: EncodedEvent(kind: 'event-$i', bytes: Uint8List(0)),
            occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        ],
      ),
    );
  }
}
