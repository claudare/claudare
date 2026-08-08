import 'dart:typed_data';

import 'package:core/src/cqrs/command/command_result.dart';
import 'package:core/src/cqrs/command/encoded_command.dart';
import 'package:core/src/cqrs/command/stored_command_write.dart';
import 'package:core/src/cqrs/event_store/event_store_administration.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/event_store_safe.dart';
import 'package:core/src/cqrs/event_store/memory/memory_event_store.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/exception/concurrency_problem.dart';
import 'package:core/src/cqrs/exception/event_store_exception.dart';
import 'package:core/src/cqrs/pattern_filter.dart';
import 'package:core/src/device_id.dart';
import 'package:test/test.dart';

void main() {
  final store = EventStoreSafe(_FailingEventStore());

  test('wraps asynchronous event-store failures', () async {
    await _expectWrapped(store.getStreamEvents('stream', 1, 0));
    await _expectWrapped(store.getStreamInfo('stream'));
    await _expectWrapped(store.saveChanges(_command(), StreamAppends.empty()));
    await _expectWrapped(store.getLocalEvents(PatternFilter.any(), 0, 1));
    await _expectWrapped(store.getLocalLastEvent(PatternFilter.any()));
    await _expectWrapped(store.getStatistics());
    await _expectWrapped(store.reset());
  });

  test('preserves concurrency problems', () async {
    final safe = EventStoreSafe(_ConcurrencyFailingEventStore());

    await expectLater(
      safe.saveChanges(_command(), StreamAppends.empty()),
      throwsA(isA<ConcurrencyProblem>()),
    );
  });
}

Future<void> _expectWrapped(Future<Object?> operation) {
  return expectLater(
    operation,
    throwsA(
      isA<EventStoreException>().having(
        (exception) => exception.cause,
        'cause',
        isA<StateError>(),
      ),
    ),
  );
}

StoredCommandWrite _command() {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return StoredCommandWrite(
    deviceId: DeviceId(1),
    encoded: EncodedCommand(kind: 'test', bytes: Uint8List(0)),
    startedAt: timestamp,
    completedAt: timestamp,
    result: CommandResult.success(),
  );
}

class _FailingEventStore extends MemoryEventStore {
  Never _fail() => throw StateError('store failed');

  @override
  Future<GetStreamEventsResult> getStreamEvents(
    String streamId,
    int count,
    int versionCursor,
  ) async => _fail();

  @override
  Future<GetStreamInfoResult?> getStreamInfo(String streamId) async => _fail();

  @override
  Future<SaveChangesResult> saveChanges(
    StoredCommandWrite command,
    StreamAppends appends,
  ) async => _fail();

  @override
  Future<GetLocalEventsResult> getLocalEvents(
    PatternFilter patternFilter,
    int sequenceNumber,
    int count,
  ) async => _fail();

  @override
  Future<GetLocalLastEventResult> getLocalLastEvent(
    PatternFilter patternFilter,
  ) async => _fail();

  @override
  Future<GetStatisticsResult> getStatistics() async => _fail();

  @override
  Future<void> reset() async => _fail();
}

class _ConcurrencyFailingEventStore extends _FailingEventStore {
  @override
  Future<SaveChangesResult> saveChanges(
    StoredCommandWrite command,
    StreamAppends appends,
  ) async => throw ConcurrencyProblem();
}
