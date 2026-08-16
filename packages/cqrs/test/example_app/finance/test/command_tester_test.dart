import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';
import 'package:test/test.dart';

import '../account_event/account.dart';
import '../command/atm_depost.dart';
import '../stream_route/account_stream_route.dart';

// testing the command tester on the example app
// TODO: these tests need to be standalone
void main() {
  group('Command tester', () {
    late TimeProvider timeProvider;
    late IdGenerator idGenerator;
    late CommandTester commandTester;

    setUp(() {
      timeProvider = FakeTimeProviderStatic.unixMilliseconds(0);
      idGenerator = IdGeneratorSequential();
      commandTester =
          CommandTester(timeProvider: timeProvider, idGenerator: idGenerator)
            ..registerEvent(const AccountAtmDepositedCodec())
            ..registerEvent(const AccountAtmWithdrawnCodec())
            ..registerEvent(const AccountInnerTransferCodec())
            ..registerEvent(const AccountOpenedCodec())
            ..registerEvent(const AccountRenamedCodec());
    });

    test('happy path', () async {
      commandTester.withEvent(
        accountStreamRoute,
        '123',
        AccountOpened(name: 'test'),
      );

      await commandTester.run(
        AtmDeposit(),
        AtmDepositInput(accountId: '123', amount: 42),
      );

      final events = await commandTester.getWrittenEvents<AccountEvent, String>(
        accountStreamRoute,
        '123',
      );
      expect(events, hasLength(1));
      expect(events.first, isA<AccountAtmDeposited>());
      expect((events.first as AccountAtmDeposited).amount, 42);
    });

    // try to append to event that does not exist
    test('propagates exception', () async {
      await expectLater(
        commandTester.run(
          AtmDeposit(),
          AtmDepositInput(accountId: '123', amount: 42),
        ),
        throwsA(isA<StreamNotFoundException>()),
      );
    });

    test('propagates application validation exception', () async {
      commandTester.withEvent2('account/123', AccountOpened(name: 'test'));

      await expectLater(
        commandTester.run(
          AtmDeposit(),
          AtmDepositInput(accountId: '123', amount: -999),
        ),
        throwsA(
          isA<CommandException>().having(
            (exception) => exception.message,
            'message',
            'amount must be positive',
          ),
        ),
      );
    });
  });
}
