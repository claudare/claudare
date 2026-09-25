import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';

void main() {
  test('EventStoreException includes its cause in the description', () {
    const error = EventStoreException(
      'Failed to append command batch',
      cause: FormatException('invalid stored bundle'),
    );

    expect(
      error.toString(),
      'EventStoreException: Failed to append command batch. '
      'Cause: FormatException: invalid stored bundle',
    );
  });

  for (final backend in eventStoreTestBackends) {
    test('${backend.name} failed append leaves no partial history', () async {
      final session = await backend.open();
      addTearDown(session.close);
      final store = session.store;
      final first = EventAppend(
        streamPath: 'one',
        encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
        occuredAt: DateTime.utc(2026),
      );
      CommandChanges changes(List<EventAppend> events) => CommandChanges(
        actor: 'test-actor',
        dependency: CommandDependency(),
        occuredAt: DateTime.utc(2026),
        locks: [
          const StreamLock(streamPath: 'one', originatingStreamVersion: null),
        ],
        events: events,
      );
      await expectLater(
        store.saveChanges(changes([first, _FailingAppend()])),
        throwsA(isA<EventStoreException>()),
      );
      expect((await store.getState()).lastCommandLogPosition, isNull);
      expect((await store.getLogEvents(0)).data, isEmpty);
      expect(await store.getStreamVersion('one'), isNull);
      await store.saveChanges(changes([first]));
      expect(
        await store.getStoredCommand(CommandId('test-actor', 1)),
        isNotNull,
      );
      expect((await store.getLogEvents(0)).data.single.position, 0);
    });

    test(
      '${backend.name} preserves the original failure stack trace',
      () async {
        final session = await backend.open();
        addTearDown(session.close);
        final trace = StackTrace.fromString('original storage failure');

        try {
          await session.store.addStoredCommand(_FailingBundle(trace));
          fail('Expected an EventStoreException');
        } on EventStoreException catch (error, caughtTrace) {
          expect(
            error.cause,
            isA<FormatException>().having(
              (cause) => cause.message,
              'message',
              'invalid stored bundle',
            ),
          );
          expect(caughtTrace.toString(), trace.toString());
        }
      },
    );
  }
}

final class _FailingAppend extends EventAppend {
  _FailingAppend()
    : super(
        streamPath: 'one',
        encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
        occuredAt: DateTime.utc(2026),
      );

  @override
  EncodedEvent get encodedEvent =>
      throw const FormatException('injected failure');
}

final class _FailingBundle extends StoredCommand {
  final StackTrace failureTrace;

  _FailingBundle(this.failureTrace)
    : super(
        commandId: const CommandId('actor-1', 1),
        dependency: CommandDependency(),
        occuredAt: DateTime.utc(2026),
        events: const [],
      );

  @override
  List<StoredCommandEvent> get events => Error.throwWithStackTrace(
    const FormatException('invalid stored bundle'),
    failureTrace,
  );
}
