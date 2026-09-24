import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

import '../command/atm_depost.dart';
import '../command/atm_withdrawal.dart';
import '../command/open_account.dart';
import '../command/rename_account.dart';
import '../command/transfer_funds_between_accounts.dart';
import '../finance_app.dart';

void main() {
  const firstAccountId = 'first';
  const secondAccountId = 'second';
  final occurredAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  late FinanceApp app;
  late EventStore eventStore;

  setUp(() async {
    eventStore = EventStore(MemoryEventDatabase());
    await eventStore.migrate();

    final runtime = CqrsRuntime(
      eventStore: eventStore,
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
    );
    app = FinanceApp(cqrsRuntime: runtime);
  });

  tearDown(() => eventStore.close());

  Future<void> openFirstAccount() => app.command.openAccount(
    const OpenAccountInput(accountId: firstAccountId, name: 'first'),
  );

  Future<void> transferToSecondAccount() async {
    await openFirstAccount();
    await app.command.openAccount(
      const OpenAccountInput(accountId: secondAccountId, name: 'second'),
    );
    await app.command.atmDeposit(
      const AtmDepositInput(accountId: firstAccountId, amount: 100),
    );
    await app.command.transferFundsBetweenAccounts(
      const TransferFundsBetweenAccountsInput(
        fromAccountId: firstAccountId,
        toAccountId: secondAccountId,
        amount: 20,
      ),
    );
  }

  test('account list starts empty', () async {
    final list = await app.readModels.accountList();

    expect(list.accounts, isEmpty);
  });

  test('total balance starts at zero', () async {
    final total = await app.readModels.totalBalance();

    expect(total.balance, 0);
  });

  test('opening an account makes its summary available', () async {
    await openFirstAccount();

    final summary = await app.readModels.accountSummary(firstAccountId);

    expect(summary.accountId, firstAccountId);
    expect(summary.name, 'first');
    expect(summary.balance, 0);
    expect(summary.transactionCount, 0);
    expect(summary.openedAt, occurredAt);
  });

  test(
    'account summary reflects deposits, withdrawals, and renaming',
    () async {
      await openFirstAccount();
      await app.command.atmDeposit(
        const AtmDepositInput(accountId: firstAccountId, amount: 100),
      );
      await app.command.atmWithdrawal(
        const AtmWithdrawalInput(accountId: firstAccountId, amount: 10),
      );
      await app.command.renameAccount(
        const RenameAccountInput(accountId: firstAccountId, newName: 'renamed'),
      );

      final summary = await app.readModels.accountSummary(firstAccountId);

      expect(summary.name, 'renamed');
      expect(summary.balance, 90);
      expect(summary.transactionCount, 2);
      expect(summary.lastTransactionAt, occurredAt);
    },
  );

  test('account list reflects commands after an earlier read', () async {
    await openFirstAccount();
    final before = await app.readModels.accountList();

    await app.command.atmDeposit(
      const AtmDepositInput(accountId: firstAccountId, amount: 40),
    );
    await app.command.renameAccount(
      const RenameAccountInput(accountId: firstAccountId, newName: 'renamed'),
    );

    final after = await app.readModels.accountList();

    expect(before.accounts[firstAccountId]!.balance, 0);
    expect(before.accounts[firstAccountId]!.name, 'first');
    expect(after.accounts[firstAccountId]!.balance, 40);
    expect(after.accounts[firstAccountId]!.name, 'renamed');
  });

  test('transfer updates both account summaries', () async {
    await transferToSecondAccount();

    final first = await app.readModels.accountSummary(firstAccountId);
    final second = await app.readModels.accountSummary(secondAccountId);

    expect(first.balance, 80);
    expect(second.balance, 20);
  });

  test('account list includes both sides of a transfer', () async {
    await transferToSecondAccount();

    final list = await app.readModels.accountList();

    expect(list.toSortedByName().map((account) => account.accountId), [
      firstAccountId,
      secondAccountId,
    ]);
    expect(list.accounts[firstAccountId]!.balance, 80);
    expect(list.accounts[secondAccountId]!.balance, 20);
  });

  test('transfer preserves the total balance', () async {
    await transferToSecondAccount();

    final total = await app.readModels.totalBalance();

    expect(total.balance, 100);
  });

  test('withdrawal beyond the balance leaves the account unchanged', () async {
    await openFirstAccount();

    await expectLater(
      app.command.atmWithdrawal(
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

    final summary = await app.readModels.accountSummary(firstAccountId);
    expect(summary.balance, 0);
    expect(summary.transactionCount, 0);
  });

  test('concurrent withdrawals cannot both spend the same balance', () async {
    await openFirstAccount();
    await app.command.atmDeposit(
      const AtmDepositInput(accountId: firstAccountId, amount: 100),
    );

    final first = app.command.atmWithdrawal(
      const AtmWithdrawalInput(accountId: firstAccountId, amount: 80),
    );
    final second = app.command.atmWithdrawal(
      const AtmWithdrawalInput(accountId: firstAccountId, amount: 80),
    );
    final results = await Future.wait([
      first.then<Object?>((_) => null, onError: (Object error) => error),
      second.then<Object?>((_) => null, onError: (Object error) => error),
    ]);

    expect(results.where((result) => result == null), hasLength(1));
    expect(results.whereType<Exception>(), hasLength(1));
    final summary = await app.readModels.accountSummary(firstAccountId);
    expect(summary.balance, 20);
  });
}
