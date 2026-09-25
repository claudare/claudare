import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    test(
      '${backend.name} preserves the original failure stack trace',
      () async {
        final session = await backend.open();
        addTearDown(session.close);
        final trace = StackTrace.fromString('original storage failure');

        try {
          await session.store.saveBundle(_FailingBundle(trace));
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

final class _FailingBundle extends CommandBundle {
  final StackTrace failureTrace;

  _FailingBundle(this.failureTrace)
    : super(
        commandId: CommandId(1, 1),
        dependency: VersionVector(),
        occuredAt: DateTime.utc(2026),
        events: const [],
      );

  @override
  bool get isValid => Error.throwWithStackTrace(
    const FormatException('invalid stored bundle'),
    failureTrace,
  );
}
