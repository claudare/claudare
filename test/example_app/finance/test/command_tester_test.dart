import 'package:core/cqrs.dart';
import 'package:core/cqrs_test_utils.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';
import 'package:test/test.dart';

import '../account_event/account.dart';
import '../command/atm_depost.dart';
import '../stream_id/account_stream_id.dart';

// testing the command tester on the example app
// TODO: these tests need to be standalone
void main() {
  group('Command tester', () {
    late TimeProvider timeProvider;
    late IdGenerator idGenerator;

    setUp(() {
      timeProvider = FakeTimeProviderStatic.unixMilliseconds(0);
      idGenerator = FakeIdGeneratorSequential();
    });

    test('happy path', () async {
      final tester = CommandTester(
        AtmDeposit(),
        timeProvider: timeProvider,
        idGenerator: idGenerator,
      );

      tester.withTypedStreamEvent(
        accountStreamId,
        "123",
        accountCodec,
        AccountOpened(name: "test"),
      );

      final ok = await tester.run(
        AtmDepositInput(accountId: "123", amount: 42),
      );

      expect(ok, isTrue);

      {
        final events = tester.getWrittenEventsOnPath("account/123");
        expect(events, hasLength(1));
        expect(events.first, isA<AccountAtmDeposited>());
        expect((events.first as AccountAtmDeposited).amount, 42);
      }

      {
        final events = tester.getWrittenEventsForPattern(accountStreamId);
        expect(events, hasLength(1));
        expect(events.first, isA<AccountAtmDeposited>());
        expect((events.first as AccountAtmDeposited).amount, 42);
      }
    });

    // try to append to event that does not exist
    test('exception', () async {
      final tester = CommandTester(
        AtmDeposit(),
        timeProvider: timeProvider,
        idGenerator: idGenerator,
      );

      final ok = await tester.run(
        AtmDepositInput(accountId: "123", amount: 42),
      );

      expect(ok, isFalse);

      expect(tester.error, isA<StreamNotFoundException>());
      expect(tester.nackMessage, null);
    });

    // testing nack handling
    // also withEvent (untyped!!!)
    test('nack', () async {
      final tester = CommandTester(
        AtmDeposit(),
        timeProvider: timeProvider,
        idGenerator: idGenerator,
      );

      tester.withEvent("account/123", AccountOpened(name: "test"));

      final ok = await tester.run(
        AtmDepositInput(accountId: "123", amount: -999),
      );

      expect(ok, isFalse);

      expect(tester.nackMessage, "amount must be positive");
      expect(tester.error, null);
    });
  });
}
