import 'dart:async';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/projection/projection_runtime.dart';
import 'package:test/test.dart';

import '../../example_app/finance/account_event/account.dart';
import '../../example_app/finance/projection/account_summary.dart';
import '../../example_app/finance/read_model/accounts_summary_read_model.dart';

// TODO: create a separate, more test-oriented example app to be used in tests
void main() {
  late EventStore eventStore;
  late RuntimeStore runtimeStore;
  late AccountSummaryProjection projection;
  late ProjectionRuntime<AccountEvent, String> runner;
  late EventRegistry eventRegistry;

  setUp(() async {
    eventStore = EventStore(MemoryEventDatabase());
    await eventStore.migrate();
    runtimeStore = RuntimeStore(MemoryRuntimeDatabase());
    await runtimeStore.initialize();
    projection = AccountSummaryProjection(AccountsSummaryReadModel());
    eventRegistry = EventRegistry()..register(const AccountAtmDepositedCodec());
    runner = ProjectionRuntime(
      projection,
      logger: const NoopLogger(),
      runtimeName: 'test',
      runtimeVersion: 1,
      runtimeStore: runtimeStore,
      eventRegistry: eventRegistry,
    );
  });

  test('replay failures use the projection failure handler', () async {
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    await eventStore.saveChanges(
      CommandChanges(
        encoded: EncodedCommand(kind: 'test', bytes: Uint8List(0)),
        startedAt: occurredAt,
        completedAt: occurredAt,
        locks: const [
          StreamLocalLock(
            streamPath: 'account/missing',
            originatingStreamVersion: 0,
          ),
        ],
        events: [
          EventAppend(
            streamPath: 'account/missing',
            encodedEvent: eventRegistry.encode(AccountAtmDeposited(amount: 1)),
            occuredAt: occurredAt,
          ),
        ],
      ),
    );

    await runner.catchupSelfLoad(eventStore);

    final failure =
        projection.failureHandler as StandardProjectionFailureHandler;
    expect(
      failure.error?.error.toString(),
      'Exception: invalid getAndStore id',
    );
    expect(
      await runtimeStore.getProjectionPosition(projection.name),
      isA<ProjectionInconsistent>(),
    );
  });

  test('live failures use the projection failure handler', () async {
    await runner.catchupSelfLoad(eventStore);
    final done = Completer<void>();
    runner.enqueue(
      EventEnvelope(
        streamPath: 'account/missing',
        encodedEvent: eventRegistry.encode(AccountAtmDeposited(amount: 1)),
        occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        localSequence: 1,
      ),
      onDone: done.complete,
    );
    await done.future;

    final failure =
        projection.failureHandler as StandardProjectionFailureHandler;
    expect(
      failure.error?.error.toString(),
      'Exception: invalid getAndStore id',
    );
    expect(
      await runtimeStore.getProjectionPosition(projection.name),
      isA<ProjectionInconsistent>(),
    );
  });
}
