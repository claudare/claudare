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
    late CommandTester commandTester;

    setUp(() {
      timeProvider = FakeTimeProviderStatic.unixMilliseconds(0);
      idGenerator = FakeIdGeneratorSequential();
      commandTester = CommandTester(
        timeProvider: timeProvider,
        idGenerator: idGenerator,
      );
    });

    test('happy path', () async {
      commandTester.withEvent(
        accountStreamId,
        "123",
        accountCodec,
        AccountOpened(name: "test"),
      );

      final result = await commandTester.run(
        AtmDeposit(),
        AtmDepositInput(accountId: "123", amount: 42),
      );

      expect(result.success, isTrue);

      final events = await commandTester.getWrittenEvents(
        accountCodec,
        accountStreamId,
        "123",
      );
      expect(events, hasLength(1));
      expect(events.first, isA<AccountAtmDeposited>());
      expect((events.first as AccountAtmDeposited).amount, 42);
    });

    // try to append to event that does not exist
    test('exception', () async {
      final result = await commandTester.run(
        AtmDeposit(),
        AtmDepositInput(accountId: "123", amount: 42),
      );

      expect(result.success, isFalse);

      expect(result.exception, isA<StreamNotFoundException>());
      expect(result.nackReason, null);
    });

    // testing nack handling
    // also withEvent (untyped!!!)
    test('nack', () async {
      commandTester.withEvent2(
        "account/123",
        accountCodec,
        AccountOpened(name: "test"),
      );

      final result = await commandTester.run(
        AtmDeposit(),
        AtmDepositInput(accountId: "123", amount: -999),
      );

      expect(result.success, isFalse);
      expect(result.nackReason, "amount must be positive");
      expect(result.exception, null);
    });
  });
}
