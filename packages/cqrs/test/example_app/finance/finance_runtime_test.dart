import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

import 'account_event/account.dart';
import 'aggregate/account_list.dart';
import 'aggregate/account_summary.dart';
import 'aggregate/total_balance.dart';
import 'command/atm_depost.dart';
import 'command/atm_withdrawal.dart';
import 'command/open_account.dart';
import 'command/rename_account.dart';
import 'command/transfer_funds_between_accounts.dart';

void main() {
  const firstAccountId = 'first';
  const secondAccountId = 'second';
  final occurredAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  late CqrsRuntime runtime;

  setUp(() async {
    runtime = _createRuntime(_PagedMemoryEventDatabase(2));
    await runtime.initialize();
  });

  tearDown(() => runtime.close());

  Future<void> recordTransferAndRename() async {
    await runtime.execute(
      OpenAccount(),
      const OpenAccountInput(accountId: firstAccountId, name: 'first'),
    );
    await runtime.execute(
      OpenAccount(),
      const OpenAccountInput(accountId: secondAccountId, name: 'second'),
    );
    await runtime.execute(
      AtmDeposit(),
      const AtmDepositInput(accountId: firstAccountId, amount: 100),
    );
    await runtime.execute(
      AtmWithdrawal(),
      const AtmWithdrawalInput(accountId: firstAccountId, amount: 10),
    );
    await runtime.execute(
      TransferFundsBetweenAccounts(),
      const TransferFundsBetweenAccountsInput(
        fromAccountId: firstAccountId,
        toAccountId: secondAccountId,
        amount: 20,
      ),
    );
    await runtime.execute(
      RenameAccount(),
      const RenameAccountInput(accountId: firstAccountId, newName: 'renamed'),
    );
  }

  test('resolves an empty account list', () async {
    final list = await runtime.resolve(AccountListAggregate(), '');

    expect(list.accounts, isEmpty);
  });

  test('command completion follows durable local persistence', () async {
    await runtime.execute(
      OpenAccount(),
      const OpenAccountInput(accountId: firstAccountId, name: 'first'),
    );

    final commands = await runtime.eventStore.getAppliedCommands(0);
    final events = await runtime.eventStore.getAppliedEvents(
      commands.single.commandId,
    );

    expect(commands, hasLength(1));
    expect(events, hasLength(1));
    expect(events.single.encodedEvent.kind, AccountOpened.kind);
  });

  test('resolves account summaries after transfers and renaming', () async {
    await recordTransferAndRename();

    final first = await runtime.resolve(
      AccountSummaryAggregate(firstAccountId),
      firstAccountId,
    );
    final second = await runtime.resolve(
      AccountSummaryAggregate(secondAccountId),
      secondAccountId,
    );

    expect(first.accountId, firstAccountId);
    expect(first.name, 'renamed');
    expect(first.balance, 70);
    expect(first.transactionCount, 3);
    expect(first.openedAt, occurredAt);
    expect(first.lastTransactionAt, occurredAt);
    expect(second.accountId, secondAccountId);
    expect(second.balance, 20);
    expect(second.transactionCount, 1);
  });

  test('resolves an account list across streams', () async {
    await recordTransferAndRename();

    final list = await runtime.resolve(AccountListAggregate(), '');

    expect(list.toSortedByName().map((account) => account.accountId), [
      firstAccountId,
      secondAccountId,
    ]);
    expect(list.accounts[firstAccountId]!.balance, 70);
    expect(list.accounts[secondAccountId]!.balance, 20);
  });

  test('total balance excludes transfers between accounts', () async {
    await recordTransferAndRename();

    final total = await runtime.resolve(TotalBalanceAggregate(), '');

    expect(total.balance, 90);
  });

  test('rejects a withdrawal that exceeds the balance', () async {
    await runtime.execute(
      OpenAccount(),
      const OpenAccountInput(accountId: firstAccountId, name: 'first'),
    );

    await expectLater(
      runtime.execute(
        AtmWithdrawal(),
        const AtmWithdrawalInput(accountId: firstAccountId, amount: 40),
      ),
      throwsA(
        isA<CommandException>().having(
          (error) => error.message,
          'message',
          'insufficient funds',
        ),
      ),
    );

    final summary = await runtime.resolve(
      AccountSummaryAggregate(firstAccountId),
      firstAccountId,
    );
    expect(summary.balance, 0);
    expect((await runtime.eventStore.getStatistics()).eventCount, 1);
  });

  test('concurrent withdrawals cannot both spend the same balance', () async {
    await runtime.execute(
      OpenAccount(),
      const OpenAccountInput(accountId: firstAccountId, name: 'first'),
    );
    await runtime.execute(
      AtmDeposit(),
      const AtmDepositInput(accountId: firstAccountId, amount: 100),
    );

    final first = runtime.execute(
      AtmWithdrawal(),
      const AtmWithdrawalInput(accountId: firstAccountId, amount: 80),
    );
    final second = runtime.execute(
      AtmWithdrawal(),
      const AtmWithdrawalInput(accountId: firstAccountId, amount: 80),
    );
    final results = await Future.wait([
      first.then<Object?>((_) => null, onError: (Object error) => error),
      second.then<Object?>((_) => null, onError: (Object error) => error),
    ]);

    expect(results.whereType<ConcurrencyProblem>(), hasLength(1));
    expect(results.where((result) => result == null), hasLength(1));
    final summary = await runtime.resolve(
      AccountSummaryAggregate(firstAccountId),
      firstAccountId,
    );
    expect(summary.balance, 20);
  });

  test('each resolve uses current events and fresh state', () async {
    await runtime.execute(
      OpenAccount(),
      const OpenAccountInput(accountId: firstAccountId, name: 'first'),
    );

    final before = await runtime.resolve(
      AccountSummaryAggregate(firstAccountId),
      firstAccountId,
    );
    await runtime.execute(
      AtmDeposit(),
      const AtmDepositInput(accountId: firstAccountId, amount: 50),
    );
    final after = await runtime.resolve(
      AccountSummaryAggregate(firstAccountId),
      firstAccountId,
    );

    expect(before.balance, 0);
    expect(after.balance, 50);
    expect(after.transactionCount, 1);
  });

  test('aggregate resolution scans every event page', () async {
    await runtime.execute(
      OpenAccount(),
      const OpenAccountInput(accountId: firstAccountId, name: 'first'),
    );
    for (final amount in [1, 2, 3, 4]) {
      await runtime.execute(
        AtmDeposit(),
        AtmDepositInput(accountId: firstAccountId, amount: amount),
      );
    }

    final summary = await runtime.resolve(
      AccountSummaryAggregate(firstAccountId),
      firstAccountId,
    );

    expect(summary.balance, 10);
    expect(summary.transactionCount, 4);
  });

  test('aggregate resolution includes promoted replicated events', () async {
    final commandId = CommandId(7, 1);
    await runtime.eventStore.stageReplicatedCommand(
      ReplicatedCommand(
        commandId: commandId,
        dependency: VersionVector(),
        encoded: EncodedCommand(
          kind: 'replicated-open-account',
          bytes: Uint8List(0),
        ),
        startedAt: occurredAt,
        completedAt: occurredAt,
        eventCount: 1,
      ),
    );
    await runtime.eventStore.stageReplicatedEvents([
      ReplicatedEvent(
        eventId: EventId(7, 1, 0),
        streamPath: 'account/$firstAccountId',
        encodedEvent: EncodedEvent(
          kind: AccountOpened.kind,
          bytes: const AccountOpenedCodec().toBytes(
            const AccountOpened(name: 'replicated'),
          ),
        ),
        occuredAt: occurredAt,
      ),
    ]);
    expect(await runtime.eventStore.promotePendingCommand(commandId), isTrue);

    final summary = await runtime.resolve(
      AccountSummaryAggregate(firstAccountId),
      firstAccountId,
    );

    expect(summary.accountId, firstAccountId);
    expect(summary.name, 'replicated');
  });
}

CqrsRuntime _createRuntime(EventDatabase eventDatabase) {
  final eventRegistry =
      EventRegistry()
        ..add(const AccountAtmDepositedCodec())
        ..add(const AccountAtmWithdrawnCodec())
        ..add(const AccountInnerTransferCodec())
        ..add(const AccountOpenedCodec())
        ..add(const AccountRenamedCodec());

  return CqrsRuntime(
    dependencies: CqrsRuntimeDependencies(
      eventDatabase: eventDatabase,
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
    ),
    eventRegistry: eventRegistry,
    runtimeName: 'finance-test',
  );
}

final class _PagedMemoryEventDatabase extends MemoryEventDatabase {
  final int pageSize;

  _PagedMemoryEventDatabase(this.pageSize);

  @override
  int get defaultEventFetchPageSize => pageSize;
}
