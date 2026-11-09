import 'dart:typed_data';

import 'package:cqrs/src/cqrs/command/command_dependency.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/log_player.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/memory_event_store.dart';
import 'package:cqrs/src/cqrs/log_filter.dart';
import 'package:test/test.dart';

void main() {
  group('LogPlayer readers', () {
    late EventStore store;
    late LogPlayer logPlayer;

    const pageSize = 2;

    setUp(() {
      store = MemoryEventStore(eventFetchPageSize: pageSize);
      logPlayer = LogPlayer(store);
    });

    test('handles empty result', () async {
      expect(await logPlayer.streamReader('test').toList(), isEmpty);
    });

    test('handles an empty log', () async {
      expect(
        await logPlayer.logReader(const LogFilter.all()).toList(),
        isEmpty,
      );
    });

    test('starts stream replay at the supplied version across pages', () async {
      await _appendCount(store, 5);
      final events = await logPlayer
          .streamReader('test', fromVersion: 1)
          .toList();
      expect(events.map((event) => event.version), [1, 2, 3, 4]);
    });

    test('starts log replay at the supplied position across pages', () async {
      await _appendCount(store, 5);
      final events = await logPlayer
          .logReader(const LogFilter.all(), fromPosition: 1)
          .toList();
      expect(events.map((event) => event.position), [1, 2, 3, 4]);
    });

    test('handles exact page size', () async {
      await _appendCount(store, pageSize);

      final events = await logPlayer.streamReader('test').toList();
      expect(events, hasLength(pageSize));
      expect(events[0].encodedEvent.kind, 'event-0');
      expect(events[1].encodedEvent.kind, 'event-1');
    });

    test('handles multiple pages', () async {
      await _appendCount(store, pageSize + 1);

      final events = await logPlayer.streamReader('test').toList();
      expect(events, hasLength(pageSize + 1));
      expect(events.map((event) => event.encodedEvent.kind), [
        'event-0',
        'event-1',
        'event-2',
      ]);
    });

    test('cancelling stops further page reads', () async {
      final controlled = _ControlledStore();
      await _appendCount(controlled, 2);
      final stream = LogPlayer(controlled).streamReader('test');

      expect(controlled.reads, 0);
      final events = await stream.take(1).toList();

      expect(events.single.version, 0);
      expect(controlled.reads, 1);
    });

    test('cancelling log replay stops further page reads', () async {
      final controlled = _ControlledStore();
      await _appendCount(controlled, 2);
      final stream = LogPlayer(controlled).logReader(const LogFilter.all());

      expect(controlled.logReads, 0);
      final events = await stream.take(1).toList();

      expect(events.single.position, 0);
      expect(controlled.logReads, 1);
    });

    test('propagates a later page read failure', () async {
      final controlled = _ControlledStore();
      await _appendCount(controlled, 2);
      final stream = LogPlayer(controlled).streamReader('test');
      final error = StateError('read failed');
      controlled.readError = error;

      await expectLater(
        stream.map((event) => event.version),
        emitsInOrder([0, emitsError(same(error)), emitsDone]),
      );

      expect(controlled.reads, 2);
    });
  });
}

class _ControlledStore extends MemoryEventStore {
  int reads = 0;
  int logReads = 0;
  StateError? readError;

  _ControlledStore() : super(eventFetchPageSize: 1);

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(
    LogFilter filter,
    int fromPosition,
  ) {
    logReads++;
    return super.getLogEvents(filter, fromPosition);
  }

  @override
  Future<PaginatedResult<StoredEvent>> getStreamEvents(
    String streamPath,
    int fromVersion,
  ) async {
    reads++;
    final error = readError;
    if (error != null && fromVersion > 0) throw error;
    return super.getStreamEvents(streamPath, fromVersion);
  }
}

Future<void> _appendCount(EventStore store, int count) async {
  for (var i = 0; i < count; i++) {
    await store.saveChanges(
      CommandChanges(
        actor: 'test-actor',
        dependency: CommandDependency(),
        occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        locks: [
          StreamLock(streamPath: 'test', originatingStreamVersion: i - 1),
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
