import 'dart:async';
import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
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
import 'account_event/account.dart';
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

    test('command completion follows durable local persistence', () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );

      final commands = await eventStore.getAppliedCommands(0);
      final events = await eventStore.getAppliedEvents(
        commands.single.commandId,
      );

      expect(commands, hasLength(1));
      expect(events, hasLength(1));
      expect(events.single.encodedEvent.kind, AccountOpened.kind);
      expect(
        (await accountsSummaryRepo.getAllSortedByNameDesc()).single.name,
        'first',
      );
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

    test('eventual dispatch accepts work while actively draining', () async {
      final blockingTotalBalance = _BlockingTotalBalanceReadModel();
      final raceApp = FinanceApp(
        dependencies: CqrsRuntimeDependencies(
          eventStore: EventStore(MemoryEventDatabase()),
          runtimeDatabase: MemoryRuntimeDatabase(),
          logger: const NoopLogger(),
          idGenerator: IdGeneratorSequential(),
          timeProvider: FakeTimeProviderStatic.zero(),
        ),
        accountSummaryRepo: AccountsSummaryReadModel(),
        totalBalanceRepo: blockingTotalBalance,
      );
      await raceApp.init();
      await raceApp.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );

      await raceApp.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 40),
      );
      await blockingTotalBalance.firstStoreStarted;
      await raceApp.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 2),
      );

      blockingTotalBalance.releaseFirstStore();
      await blockingTotalBalance.secondStoreCompleted;

      expect(await blockingTotalBalance.get(), 42);
    });

    test('eventual dispatch accepts work after becoming empty', () async {
      final trackingTotalBalance = _TrackingTotalBalanceReadModel();
      final raceApp = FinanceApp(
        dependencies: CqrsRuntimeDependencies(
          eventStore: EventStore(MemoryEventDatabase()),
          runtimeDatabase: MemoryRuntimeDatabase(),
          logger: const NoopLogger(),
          idGenerator: IdGeneratorSequential(),
          timeProvider: FakeTimeProviderStatic.zero(),
        ),
        accountSummaryRepo: AccountsSummaryReadModel(),
        totalBalanceRepo: trackingTotalBalance,
      );
      await raceApp.init();
      await raceApp.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );

      await raceApp.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 40),
      );
      await trackingTotalBalance.waitForStores(1);
      await raceApp.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 2),
      );
      await trackingTotalBalance.waitForStores(2);

      expect(await trackingTotalBalance.get(), 42);
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
        expect(accountPosition.scannedThroughLocalSequence, 1);

        final totalPosition =
            await store.getProjectionPosition('total-balance')
                as ProjectionAtSequence;
        expect(totalPosition.scannedThroughLocalSequence, 1);
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

    test('startup replay scans every event page', () async {
      final pagedEventStore = EventStore(
        MemoryEventDatabase(),
        eventFetchPageSize: 2,
      );
      final producer = FinanceApp(
        dependencies: CqrsRuntimeDependencies(
          eventStore: pagedEventStore,
          runtimeDatabase: MemoryRuntimeDatabase(),
          logger: const NoopLogger(),
          idGenerator: IdGeneratorSequential(),
          timeProvider: FakeTimeProviderStatic.zero(),
        ),
        accountSummaryRepo: AccountsSummaryReadModel(),
        totalBalanceRepo: TotalBalanceReadModel(),
      );
      await producer.init();
      await producer.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      for (final amount in [1, 2, 3, 4]) {
        await producer.command.atmDeposit.runThrowable(
          AtmDepositInput(accountId: firstAccountId, amount: amount),
        );
      }

      final replayedAccounts = AccountsSummaryReadModel();
      final replayedTotal = TotalBalanceReadModel();
      final consumer = FinanceApp(
        dependencies: CqrsRuntimeDependencies(
          eventStore: pagedEventStore,
          runtimeDatabase: MemoryRuntimeDatabase(),
          logger: const NoopLogger(),
          idGenerator: IdGeneratorSequential(),
          timeProvider: FakeTimeProviderStatic.zero(),
        ),
        accountSummaryRepo: replayedAccounts,
        totalBalanceRepo: replayedTotal,
      );

      await consumer.init();

      final account = (await replayedAccounts.getAllSortedByNameDesc()).single;
      expect(account.balance, 10);
      expect(account.transactionCount, 4);
      expect(await replayedTotal.get(), 10);
    });

    test('startup replay includes promoted replicated events', () async {
      final commandId = CommandId(7, 1);
      final replicatedCommand = ReplicatedCommand(
        commandId: commandId,
        dependency: VersionVector(),
        encoded: EncodedCommand(
          kind: 'replicated-open-account',
          bytes: Uint8List(0),
        ),
        startedAt: t0,
        completedAt: t0,
        eventCount: 1,
      );
      await eventStore.stageReplicatedCommand(replicatedCommand);
      await eventStore.stageReplicatedEvents([
        ReplicatedEvent(
          eventId: EventId(7, 1, 0),
          streamPath: 'account/$firstAccountId',
          encodedEvent: EncodedEvent(
            kind: AccountOpened.kind,
            bytes: const AccountOpenedCodec().toBytes(
              AccountOpened(name: 'replicated'),
            ),
          ),
          occuredAt: t0,
        ),
      ]);
      expect(await eventStore.promotePendingCommand(commandId), isTrue);

      await app.init();

      final account =
          (await accountsSummaryRepo.getAllSortedByNameDesc()).single;
      expect(account.accountId, firstAccountId);
      expect(account.name, 'replicated');
    });

    test('matching projection versions catch up without resetting', () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      accountsSummaryRepo.summaries['stale'] = AccountSummary(
        accountId: 'stale',
        name: 'stale',
        balance: 0,
        transactionCount: 0,
        openedAt: t0,
        lastTransactionAt: t0,
      );

      await app.init();

      expect(accountsSummaryRepo.summaries, contains('stale'));
    });

    test('manual rebuild resets and fully replays', () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      accountsSummaryRepo.summaries['stale'] = AccountSummary(
        accountId: 'stale',
        name: 'stale',
        balance: 0,
        transactionCount: 0,
        openedAt: t0,
        lastTransactionAt: t0,
      );

      await app.recreateProjections();

      expect(accountsSummaryRepo.summaries, isNot(contains('stale')));
      final accounts = await accountsSummaryRepo.getAllSortedByNameDesc();
      expect(accounts.single.name, 'first');
    });

    test('interrupted projection state resets and fully replays', () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      accountsSummaryRepo.summaries['stale'] = AccountSummary(
        accountId: 'stale',
        name: 'stale',
        balance: 0,
        transactionCount: 0,
        openedAt: t0,
        lastTransactionAt: t0,
      );
      await runtimeDatabase.setProjectionState(
        'account-summary',
        const RuntimeProjectionState(
          version: 1,
          applyingThroughLocalSequence: 2,
          scannedThroughLocalSequence: 1,
        ),
      );

      await app.init();

      expect(accountsSummaryRepo.summaries, isNot(contains('stale')));
      final accounts = await accountsSummaryRepo.getAllSortedByNameDesc();
      expect(accounts.single.name, 'first');
      final position =
          await RuntimeStore(
                runtimeDatabase,
              ).getProjectionPosition('account-summary')
              as ProjectionAtSequence;
      expect(position.version, 1);
      expect(position.scannedThroughLocalSequence, 1);
    });

    test('manual replay rebuilds identical read models', () async {
      await app.command.openAccount.runThrowable(
        OpenAccountInput(name: 'first'),
      );
      await app.command.atmDeposit.runThrowable(
        AtmDepositInput(accountId: firstAccountId, amount: 40),
      );

      await app.recreateProjections();

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
      expect(position.scannedThroughLocalSequence, 1);
    });
  });
}

class _BlockingTotalBalanceReadModel extends TotalBalanceReadModel {
  final _firstStoreStarted = Completer<void>();
  final _releaseFirstStore = Completer<void>();
  final _secondStoreCompleted = Completer<void>();
  var _storeCount = 0;

  Future<void> get firstStoreStarted => _firstStoreStarted.future;
  Future<void> get secondStoreCompleted => _secondStoreCompleted.future;

  void releaseFirstStore() => _releaseFirstStore.complete();

  @override
  Future<void> store(int value) async {
    _storeCount++;
    if (_storeCount == 1) {
      _firstStoreStarted.complete();
      await _releaseFirstStore.future;
    }
    await super.store(value);
    if (_storeCount == 2) {
      _secondStoreCompleted.complete();
    }
  }
}

class _TrackingTotalBalanceReadModel extends TotalBalanceReadModel {
  final _storeWaiters = <int, Completer<void>>{};
  var _storeCount = 0;

  Future<void> waitForStores(int count) {
    if (_storeCount >= count) return Future.value();
    return (_storeWaiters[count] ??= Completer<void>()).future;
  }

  @override
  Future<void> store(int value) async {
    await super.store(value);
    _storeCount++;
    final completedCounts =
        _storeWaiters.keys.where((count) => count <= _storeCount).toList();
    for (final count in completedCounts) {
      _storeWaiters.remove(count)!.complete();
    }
  }
}
