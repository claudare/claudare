import 'dart:convert';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

import '../account_event/account.dart';
import '../command/record_expense.dart';
import '../finance_app.dart';
import '../paths.dart';

void main() {
  Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));
  Uint8List receipt(int amount) => bytes('{"amount": $amount}');

  late MemoryEventStore events;
  late _ReceiptBlobStore blobs;
  late CqrsTestRuntime runtime;
  late FinanceApp app;

  setUp(() {
    events = MemoryEventStore();
    blobs = _ReceiptBlobStore();
    runtime = CqrsTestRuntime(eventStore: events, blobStore: blobs);
    app = FinanceApp(cqrsRuntime: runtime);
  });

  Future<void> fundAccount() async {
    await app.command.openAccount(accountId: 'one', name: 'First');
    await app.command.atmDeposit(accountId: 'one', amount: 100);
  }

  Future<void> record(int amount) => app.command.recordExpense(
    accountId: 'one',
    receiptBytes: receipt(amount),
  );

  Future<void> expectRejected(
    Future<void> Function() action,
    Matcher error,
  ) async {
    final position = (await events.getState()).lastEventLogPosition;
    final previousSaves = blobs.savedIds.length;
    await expectLater(action(), throwsA(error));
    expect((await events.getState()).lastEventLogPosition, position);
    expect(blobs.savedIds, hasLength(previousSaves));
  }

  test('expense event references the saved original receipt', () async {
    await fundAccount();
    final original = bytes(' { "amount": 25 }\n');

    await app.command.recordExpense(accountId: 'one', receiptBytes: original);

    final stored = await runtime.streamReader(accountStream('one')).scan().last;
    final expense = runtime.eventRegistry.decode<AccountExpenseRecorded>(
      stored.encodedEvent,
    );
    expect(expense.accountId, 'one');
    expect(expense.amount, 25);
    expect(blobs.savedIds, [expense.receiptBlobId]);
    expect(await app.query.receipt(expense.receiptBlobId), original);
  });

  test(
    'expense history preserves order and allows receipt retrieval',
    () async {
      await fundAccount();
      await record(25);
      await record(10);

      final expenses = await app.query.expenses('one');

      expect(expenses.map((expense) => expense.amount), [25, 10]);
      for (final expense in expenses) {
        expect(
          await app.query.receipt(expense.receiptBlobId),
          receipt(expense.amount),
        );
      }
      expect(await app.query.expenses('other'), isEmpty);
    },
  );

  test('missing receipt returns null', () async {
    expect(await app.query.receipt('missing'), isNull);
  });

  test('expense updates account summary', () async {
    await fundAccount();
    await record(25);

    final summary = await app.query.accountSummary('one');
    expect(summary.balance, 75);
    expect(summary.transactionCount, 2);
    expect(
      summary.lastTransactionAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  });

  test('expense updates account list after an earlier read', () async {
    await fundAccount();
    await app.query.accountList();
    await record(25);

    final list = await app.query.accountList();
    expect(list.accounts['one']!.balance, 75);
    expect(list.accounts['one']!.transactionCount, 2);
  });

  test('expense updates total balance', () async {
    await fundAccount();
    await record(25);

    expect((await app.query.totalBalance()).balance, 75);
  });

  for (final operation in ['withdrawal', 'transfer', 'expense']) {
    test(
      '$operation cannot spend the balance consumed by an expense',
      () async {
        await fundAccount();
        await app.command.openAccount(accountId: 'two', name: 'Second');
        await record(60);

        await expectRejected(
          () => switch (operation) {
            'withdrawal' => app.command.atmWithdrawal(
              accountId: 'one',
              amount: 50,
            ),
            'transfer' => app.command.transferFundsBetweenAccounts(
              fromAccountId: 'one',
              toAccountId: 'two',
              amount: 50,
            ),
            _ => record(50),
          },
          isA<CommandException>().having(
            (error) => error.message,
            'message',
            'insufficient funds',
          ),
        );
      },
    );
  }

  for (final invalid in ['{', '[]', 'null']) {
    test('rejects malformed receipt $invalid without persistence', () async {
      await fundAccount();
      await expectRejected(
        () => app.command.recordExpense(
          accountId: 'one',
          receiptBytes: bytes(invalid),
        ),
        isA<CommandException>(),
      );
    });
  }

  for (final amount in ['0', '-1', '1.5', '"25"', 'null', 'true']) {
    test('rejects invalid amount $amount without persistence', () async {
      await fundAccount();
      await expectRejected(
        () => app.command.recordExpense(
          accountId: 'one',
          receiptBytes: bytes('{"amount": $amount}'),
        ),
        isA<CommandException>(),
      );
    });
  }

  test('rejects missing amount without persistence', () async {
    await fundAccount();
    await expectRejected(
      () => app.command.recordExpense(
        accountId: 'one',
        receiptBytes: bytes('{}'),
      ),
      isA<CommandException>(),
    );
  });

  test('rejects invalid UTF-8 without persistence', () async {
    await fundAccount();
    await expectRejected(
      () => app.command.recordExpense(
        accountId: 'one',
        receiptBytes: Uint8List.fromList([255]),
      ),
      isA<CommandException>(),
    );
  });

  test('rejects missing account without persistence', () async {
    await expectRejected(() => record(25), isA<StreamNotFoundException>());
  });

  test('blob save failure prevents the expense event', () async {
    await fundAccount();
    final failure = Exception('receipt save failed');
    blobs.failure = failure;

    await expectRejected(() => record(25), same(failure));
    expect(await app.query.expenses('one'), isEmpty);
  });

  test('uploading the same receipt creates separate expenses', () async {
    await fundAccount();
    await record(25);
    await record(25);

    final expenses = await app.query.expenses('one');
    expect(expenses, hasLength(2));
    expect(
      expenses.map((expense) => expense.receiptBlobId).toSet(),
      hasLength(2),
    );
    expect((await app.query.accountSummary('one')).balance, 50);
  });

  test('an expense can spend the entire remaining balance', () async {
    await fundAccount();
    await record(100);

    expect((await app.query.accountSummary('one')).balance, 0);
  });

  test('receipt bytes are captured before asynchronous execution', () async {
    await fundAccount();
    final original = receipt(25);
    final command = RecordExpense(accountId: 'one', receiptBytes: original);
    original.fillRange(0, original.length, 0);

    await runtime.execute(command);

    final expense = (await app.query.expenses('one')).single;
    expect(await app.query.receipt(expense.receiptBlobId), receipt(25));
  });
}

class _ReceiptBlobStore extends MemoryBlobStore {
  final savedIds = <String>[];
  Exception? failure;

  @override
  Future<void> save(String blobId, Uint8List data) async {
    final error = failure;
    if (error != null) throw error;
    await super.save(blobId, data);
    savedIds.add(blobId);
  }
}
