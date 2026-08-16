import 'dart:async';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/projection/projection_runtime.dart';
import 'package:test/test.dart';

import '../../example_app/finance/account_event/account.dart';
import '../../example_app/finance/projection/account_summary.dart';
import '../../example_app/finance/read_model/accounts_summary_read_model.dart';
import '../../example_app/finance/stream_id/account_stream_id.dart';

// TODO: create a separate, more test-oriented example app to be used in tests
void main() {
  late EventStore eventStore;
  late RuntimeStore runtimeStore;
  late AccountSummaryProjection projection;
  late ProjectionRuntime<AccountEvent, String> runner;

  setUp(() async {
    eventStore = EventStore(MemoryEventDatabase());
    await eventStore.migrate();
    runtimeStore = RuntimeStore(MemoryRuntimeDatabase());
    await runtimeStore.initialize();
    projection = AccountSummaryProjection(AccountsSummaryReadModel());
    runner = ProjectionRuntime(
      projection,
      logger: const NoopLogger(),
      runtimeName: 'test',
      runtimeVersion: 1,
      runtimeStore: runtimeStore,
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
            streamId: 'account/missing',
            originatingStreamVersion: 0,
          ),
        ],
        events: [
          EventAppend(
            streamId: 'account/missing',
            encodedEvent: accountCodec.encode(AccountAtmDeposited(amount: 1)),
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
        streamIdStr: 'account/missing',
        streamIdData: 'missing',
        streamIdPattern: accountStreamId,
        event: AccountAtmDeposited(amount: 1),
        metadata: EventMetadata(
          occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
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
