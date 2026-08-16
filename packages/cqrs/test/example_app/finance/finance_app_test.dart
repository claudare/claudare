import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';
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

    late EventStore eventStore;
    late MemoryRuntimeDatabase runtimeDatabase;
    late TimeProvider commandTimeProvider;
    late IdGenerator commandIdGenerator;
    late AccountsSummaryReadModel accountsSummaryRepo;
    late TotalBalanceReadModel totalBalanceRepo;
    late FinanceApp app;

    setUp(() async {
      eventStore = EventStore(MemoryEventDatabase());
      runtimeDatabase = MemoryRuntimeDatabase();
      commandTimeProvider = FakeTimeProviderStatic.zero();
      commandIdGenerator = IdGeneratorSequential();
      accountsSummaryRepo = AccountsSummaryReadModel();
      totalBalanceRepo = TotalBalanceReadModel();

      app = FinanceApp(
        dependencies: CqrsRuntimeDependencies(
          eventStore: eventStore,
          runtimeDatabase: runtimeDatabase,
          logger: const NoopLogger(),
          idGenerator: commandIdGenerator,
          timeProvider: commandTimeProvider,
        ),
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
          isA<CommandException>().having(
            (error) => error.message,
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

    test(
      'runtime owns progress for live events and intentional no-ops',
      () async {
        await app.command.openAccount.runThrowable(
          OpenAccountInput(name: 'first'),
        );

        final store = RuntimeStore(runtimeDatabase);
        final accountPosition =
            await store.getProjectionPosition('account-summary')
                as ProjectionAtSequence;
        expect(accountPosition.sequence, 1);

        await Future<void>.delayed(const Duration(milliseconds: 10));
        final totalPosition =
            await store.getProjectionPosition('total-balance')
                as ProjectionAtSequence;
        expect(totalPosition.sequence, 1);
        expect(await totalBalanceRepo.get(), 0);
      },
    );

    test('resumes without reapplying stored events', () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      await app.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 40),
      );

      await app.init();

      final accounts = await accountsSummaryRepo.getAllSortedByNameDesc();
      expect(accounts.single.balance, 40);
      expect(accounts.single.transactionCount, 1);
    });

    test('manual replay rebuilds identical read models', () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      await app.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 40),
      );

      await app.rerunProjections();

      final accounts = await accountsSummaryRepo.getAllSortedByNameDesc();
      expect(accounts.single.balance, 40);
      expect(accounts.single.transactionCount, 1);
      expect(await totalBalanceRepo.get(), 40);
    });

    test('runtime version change rebuilds projections', () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      await app.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 40),
      );

      final upgraded = FinanceApp(
        dependencies: CqrsRuntimeDependencies(
          eventStore: eventStore,
          runtimeDatabase: runtimeDatabase,
          logger: const NoopLogger(),
          idGenerator: commandIdGenerator,
          timeProvider: commandTimeProvider,
        ),
        accountSummaryRepo: accountsSummaryRepo,
        totalBalanceRepo: totalBalanceRepo,
        runtimeVersion: 2,
      );
      await upgraded.init();

      final accounts = await accountsSummaryRepo.getAllSortedByNameDesc();
      expect(accounts.single.balance, 40);
      expect(accounts.single.transactionCount, 1);
      expect(await totalBalanceRepo.get(), 40);
    });

    test('inconsistent apply boundary triggers reset and replay', () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      final store = RuntimeStore(runtimeDatabase);
      final error = StateError('interrupted apply');
      await expectLater(
        store.advanceProjection(
          'account-summary',
          1,
          2,
          () async => throw error,
        ),
        throwsA(same(error)),
      );

      await app.init();

      final accounts = await accountsSummaryRepo.getAllSortedByNameDesc();
      expect(accounts.single.name, 'first');
      final position =
          await store.getProjectionPosition('account-summary')
              as ProjectionAtSequence;
      expect(position.sequence, 1);
    });
  });
}
