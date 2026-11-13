import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

import '../finance_app.dart';

void main() {
  const firstAccountId = 'first';
  const secondAccountId = 'second';
  final occurredAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  late FinanceApp app;
  late CqrsTestRuntime runtime;

  setUp(() async {
    runtime = CqrsTestRuntime();
    app = FinanceApp(cqrsRuntime: runtime);
  });

  Future<void> openFirstAccount() =>
      app.command.openAccount(accountId: firstAccountId, name: 'first');

  Future<void> transferToSecondAccount() async {
    await openFirstAccount();
    await app.command.openAccount(accountId: secondAccountId, name: 'second');
    await app.command.atmDeposit(accountId: firstAccountId, amount: 100);
    await app.command.transferFundsBetweenAccounts(
      fromAccountId: firstAccountId,
      toAccountId: secondAccountId,
      amount: 20,
    );
  }

  test('account list starts empty', () async {
    final list = await app.query.accountList();

    expect(list.accounts, isEmpty);
  });

  test('total balance starts at zero', () async {
    final total = await app.query.totalBalance();

    expect(total.balance, 0);
  });

  test('opening an account makes its summary available', () async {
    await openFirstAccount();

    final summary = await app.query.accountSummary(firstAccountId);

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
      await app.command.atmDeposit(accountId: firstAccountId, amount: 100);
      await app.command.atmWithdrawal(accountId: firstAccountId, amount: 10);
      await app.command.renameAccount(
        accountId: firstAccountId,
        newName: 'renamed',
      );

      final summary = await app.query.accountSummary(firstAccountId);

      expect(summary.name, 'renamed');
      expect(summary.balance, 90);
      expect(summary.transactionCount, 2);
      expect(summary.lastTransactionAt, occurredAt);
    },
  );

  test('account list reflects commands after an earlier read', () async {
    await openFirstAccount();
    final before = await app.query.accountList();

    await app.command.atmDeposit(accountId: firstAccountId, amount: 40);
    await app.command.renameAccount(
      accountId: firstAccountId,
      newName: 'renamed',
    );

    final after = await app.query.accountList();

    expect(before.accounts[firstAccountId]!.balance, 0);
    expect(before.accounts[firstAccountId]!.name, 'first');
    expect(after.accounts[firstAccountId]!.balance, 40);
    expect(after.accounts[firstAccountId]!.name, 'renamed');
  });

  test('summary queries leave earlier results unchanged', () async {
    await openFirstAccount();
    final before = await app.query.accountSummary(firstAccountId);

    await app.command.atmDeposit(accountId: firstAccountId, amount: 40);
    final after = await app.query.accountSummary(firstAccountId);

    expect(before.balance, 0);
    expect(before.transactionCount, 0);
    expect(after.balance, 40);
    expect(after.transactionCount, 1);
  });

  test('total balance queries leave earlier results unchanged', () async {
    await openFirstAccount();
    final before = await app.query.totalBalance();

    await app.command.atmDeposit(accountId: firstAccountId, amount: 40);
    final after = await app.query.totalBalance();

    expect(before.balance, 0);
    expect(after.balance, 40);
  });

  test('permanent deletion clears an account summary', () async {
    await transferToSecondAccount();

    await runtime.execute(const _DeleteAccount(firstAccountId));
    final summary = await app.query.accountSummary(firstAccountId);

    expect(summary.accountId, isEmpty);
    expect(summary.name, isEmpty);
    expect(summary.balance, 0);
    expect(summary.transactionCount, 0);
    expect(summary.openedAt.millisecondsSinceEpoch, 0);
    expect(summary.lastTransactionAt.millisecondsSinceEpoch, 0);
  });

  test('permanent deletion removes an account from the list', () async {
    await transferToSecondAccount();
    final before = await app.query.accountList();

    await runtime.execute(const _DeleteAccount(firstAccountId));
    final after = await app.query.accountList();

    expect(
      before.accounts.keys,
      containsAll([firstAccountId, secondAccountId]),
    );
    expect(after.accounts.keys, [secondAccountId]);
    expect(after.accounts[secondAccountId]!.balance, 20);
  });

  test(
    'permanent deletion subtracts only the deleted account balance',
    () async {
      await transferToSecondAccount();

      await runtime.execute(const _DeleteAccount(firstAccountId));
      final total = await app.query.totalBalance();

      expect(total.balance, 20);
    },
  );

  test('transfer updates both account summaries', () async {
    await transferToSecondAccount();

    final first = await app.query.accountSummary(firstAccountId);
    final second = await app.query.accountSummary(secondAccountId);

    expect(first.balance, 80);
    expect(second.balance, 20);
  });

  test('account list includes both sides of a transfer', () async {
    await transferToSecondAccount();

    final list = await app.query.accountList();

    expect(list.toSortedByName().map((account) => account.accountId), [
      firstAccountId,
      secondAccountId,
    ]);
    expect(list.accounts[firstAccountId]!.balance, 80);
    expect(list.accounts[secondAccountId]!.balance, 20);
  });

  test('transfer preserves the total balance', () async {
    await transferToSecondAccount();

    final total = await app.query.totalBalance();

    expect(total.balance, 100);
  });

  test('withdrawal beyond the balance leaves the account unchanged', () async {
    await openFirstAccount();

    await expectLater(
      app.command.atmWithdrawal(accountId: firstAccountId, amount: 40),
      throwsA(
        isA<CommandException>().having(
          (error) => error.message,
          'message',
          'insufficient funds',
        ),
      ),
    );

    final summary = await app.query.accountSummary(firstAccountId);
    expect(summary.balance, 0);
    expect(summary.transactionCount, 0);
  });

  test('concurrent withdrawals cannot both spend the same balance', () async {
    await openFirstAccount();
    await app.command.atmDeposit(accountId: firstAccountId, amount: 100);

    final first = app.command.atmWithdrawal(
      accountId: firstAccountId,
      amount: 80,
    );
    final second = app.command.atmWithdrawal(
      accountId: firstAccountId,
      amount: 80,
    );
    final results = await Future.wait([
      first.then<Object?>((_) => null, onError: (Object error) => error),
      second.then<Object?>((_) => null, onError: (Object error) => error),
    ]);

    expect(results.where((result) => result == null), hasLength(1));
    expect(results.whereType<Exception>(), hasLength(1));
    final summary = await app.query.accountSummary(firstAccountId);
    expect(summary.balance, 20);
  });
}

class _DeleteAccount implements Command {
  final String accountId;

  const _DeleteAccount(this.accountId);

  @override
  Future<void> handle(CommandContextApi ctx) =>
      ctx.stream('account/$accountId').delete();
}
