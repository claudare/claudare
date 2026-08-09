import 'package:core/cqrs.dart';
import 'package:core/src/device_id.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:test/test.dart';

import 'command/atm_depost.dart';
import 'command/atm_withdrawal.dart';
import 'command/open_account.dart';
import 'command/rename_account.dart';
import 'command/transfer_funds_between_accounts.dart';
import 'finance_app.dart';
import 'read_model/accounts_summary_read_model.dart';
import 'read_model/total_balance_read_model.dart';

void main() {
  group('Finance App Example', () {
    const firstAccountId = 'AAAAAAAAAAAAAAAAAAAAAA';
    const secondAccountId = 'AAAAAAAAAAAAAAAAAAAAAQ';
    final t0 = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    late MemoryEventStore eventStore;
    late MemoryRuntimeRepo runtimeRepo;
    late TimeProvider commandTimeProvider;
    late IdGenerator commandIdGenerator;
    late AccountsSummaryReadModel accountsSummaryRepo;
    late TotalBalanceReadModel totalBalanceRepo;
    late FinanceApp app;

    setUp(() async {
      eventStore = MemoryEventStore();
      runtimeRepo = MemoryRuntimeRepo();
      commandTimeProvider = FakeTimeProviderStatic.zero();
      commandIdGenerator = IdGeneratorSequential();
      accountsSummaryRepo = AccountsSummaryReadModel();
      totalBalanceRepo = TotalBalanceReadModel();

      app = FinanceApp(
        config: CqrsRuntimeConfig(
          eventStore: eventStore,
          runtimeRepo: runtimeRepo,
          logger: const NoopLogger(),
          idGenerator: commandIdGenerator,
          timeProvider: commandTimeProvider,
          eventStorePageSize: 10,
        ),
        deviceId: DeviceId(1),
        accountSummaryRepo: accountsSummaryRepo,
        totalBalanceRepo: totalBalanceRepo,
      );
      await app.init();
    });

    test('app initializes', () async {});

    test('rough happy path', () async {
      // first ops
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      await app.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 100),
      );
      await app.command.atmWithdrawal.runThrowable(
        AtmWithdrawalInput(accountId: firstAccountId, amount: 10),
      );

      final firstAccounts = await accountsSummaryRepo.getAllSortedByNameDesc();
      expect(firstAccounts, hasLength(1));
      expect(firstAccounts.first.name, equals('first'));
      expect(
        firstAccounts.first.accountId,
        firstAccountId,
      ); // TODO: work on better testing for this
      expect(firstAccounts.first.balance, 90);
      expect(firstAccounts.first.transactionCount, 2);
      expect(firstAccounts.first.openedAt, t0);
      expect(firstAccounts.first.lastTransactionAt, t0);

      // second ops
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'second'),
      );

      await app.command.transferFundsBetweenAccounts.runThrowable(
        TransferFundsBetweenAccountsInput(
          fromAccountId: firstAccountId,
          toAccountId: secondAccountId,
          amount: 20,
        ),
      );
      await app.command.renameAccount.runThrowable(
        RenameAccountInput(accountId: firstAccountId, newName: 'renamed'),
      );

      final secondAccounts = await accountsSummaryRepo.getAllSortedByNameDesc();
      expect(secondAccounts, hasLength(2));

      expect(secondAccounts.first.name, equals('renamed'));
      expect(secondAccounts.first.balance, 70);

      expect(secondAccounts.last.name, equals('second'));
      expect(secondAccounts.last.balance, 20);
    });

    test('handles negative balance operations', () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      expect(
        () => app.command.atmWithdrawal.runThrowable(
          AtmWithdrawalInput(accountId: firstAccountId, amount: 40),
        ),
        throwsA(
          isA<CommandNack>().having(
            (e) => e.message,
            'message',
            'insufficient funds',
          ),
        ),
      );
    });

    test('handles concurrency errors', () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      await app.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 100),
      );

      final f1 = app.command.atmWithdrawal.runThrowable(
        AtmWithdrawalInput(accountId: firstAccountId, amount: 80),
      );
      final f2 = app.command.atmWithdrawal.runThrowable(
        AtmWithdrawalInput(accountId: firstAccountId, amount: 80),
      );

      // Attach handlers immediately. Ugly but works
      final r1 = f1.then<Object?>((_) => null, onError: (Object e) => e);
      final r2 = f2.then<Object?>((_) => null, onError: (Object e) => e);

      final results = await Future.wait([r1, r2]);
      final errors = results.where((r) => r != null).toList();

      expect(errors.length, 1);
      expect(errors.single, isA<ConcurrencyProblem>());

      final accounts = await accountsSummaryRepo.getAllSortedByNameDesc();
      expect(accounts.single.balance, 20);
    });

    test('eventual consistency', () async {
      final initialTotalBalance = await app.readModel.totalBalance.get();

      expect(initialTotalBalance, 0);

      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      await app.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 100),
      );
      await app.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 50),
      );

      // TODO: currently no way to wait for the eventual projection to stop resolving
      // this will need to be implemented, atleast for testing
      await Future.delayed(Duration(milliseconds: 10));

      final newTotalBalance = await app.readModel.totalBalance.get();

      expect(newTotalBalance, 150);
    });
  });
}
