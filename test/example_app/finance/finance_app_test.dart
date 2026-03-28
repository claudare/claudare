import 'package:core/src/cqrs.dart';
import 'package:core/src/cqrs/exception/command_nack.dart';
import 'package:core/src/cqrs_test_utils.dart';
import 'package:test/test.dart';

import 'command/atm_depost.dart';
import 'command/atm_withdrawal.dart';
import 'command/open_account.dart';
import 'command/rename_account.dart';
import 'command/transfer_funds_between_accounts.dart';
import 'finance_app.dart';
import 'read_model/accounts_summary_read_model.dart';

void main() {
  group('Finance App Example', () {
    final t0 = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    late MemoryEventStore eventStore;
    late TimeProvider commandTimeProvider;
    late IdGenerator commandIdGenerator;
    late AccountsSummaryReadModel accountsSummaryRepo;
    late FinanceApp app;

    setUp(() async {
      eventStore = MemoryEventStore(
        timeProvider: FakeTimeProviderStatic.zero(),
      );
      commandTimeProvider = FakeTimeProviderStatic.zero();
      commandIdGenerator = FakeIdGeneratorSequential();
      accountsSummaryRepo = AccountsSummaryReadModel();

      app = FinanceApp(
        eventStore: eventStore,
        config: CqrsRuntimeConfig(
          idGenerator: commandIdGenerator,
          timeProvider: commandTimeProvider,
          eventStorePageSize: 10,
        ),
        deviceId: DeviceId(1),
        accountSummaryRepo: accountsSummaryRepo,
      );
      await app.init();
    });

    test("app initializes", () async {});

    test("rough happy path", () async {
      // first ops
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: "first"),
      );
      await app.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: "1", amount: 100),
      );
      await app.command.atmWithdrawal.runThrowable(
        AtmWithdrawalInput(accountId: "1", amount: 10),
      );

      final firstAccounts = await accountsSummaryRepo.getAllSortedByNameDesc();
      expect(firstAccounts, hasLength(1));
      expect(firstAccounts.first.name, equals("first"));
      expect(
        firstAccounts.first.accountId,
        "1",
      ); // TODO: work on better testing for this
      expect(firstAccounts.first.balance, 90);
      expect(firstAccounts.first.transactionCount, 2);
      expect(firstAccounts.first.openedAt, t0);
      expect(firstAccounts.first.lastTransactionAt, t0);

      // second ops
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: "second"),
      );

      await app.command.transferFundsBetweenAccounts.runThrowable(
        TransferFundsBetweenAccountsInput(
          fromAccountId: "1",
          toAccountId: "2",
          amount: 20,
        ),
      );
      await app.command.renameAccount.runThrowable(
        RenameAccountInput(accountId: "1", newName: "first-renamed"),
      );

      final secondAccounts = await accountsSummaryRepo.getAllSortedByNameDesc();
      expect(secondAccounts, hasLength(2));

      // print("FIRST: ${secondAccounts.first}");
      // print("SECOND: ${secondAccounts.last}");

      expect(secondAccounts.first.name, equals("first-renamed"));
      expect(secondAccounts.first.balance, 70);

      expect(secondAccounts.last.name, equals("second"));
      expect(secondAccounts.last.balance, 20);
    });

    test("handles negative balance operations", () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: "first"),
      );
      expect(
        () => app.command.atmWithdrawal.runThrowable(
          AtmWithdrawalInput(accountId: "1", amount: 40),
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

    test("handles concurrency errors", () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: "first"),
      );
      await app.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: "1", amount: 100),
      );

      final f1 = app.command.atmWithdrawal.runThrowable(
        AtmWithdrawalInput(accountId: "1", amount: 80),
      );
      final f2 = app.command.atmWithdrawal.runThrowable(
        AtmWithdrawalInput(accountId: "1", amount: 80),
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
  });
}
