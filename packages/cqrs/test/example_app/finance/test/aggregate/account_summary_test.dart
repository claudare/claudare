import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

import '../../account_event/account.dart';
import '../../aggregate/account_summary.dart';

void main() {
  final openedAt = DateTime.utc(2026, 1, 1);
  final depositedAt = DateTime.utc(2026, 1, 2);
  final withdrawnAt = DateTime.utc(2026, 1, 3);
  final transferredAt = DateTime.utc(2026, 1, 4);

  group('AccountSummaryAggregate', () {
    test('starts empty and opens the selected account', () {
      final tester = AggregateTester(AccountSummaryAggregate('one'));

      expect(tester.run().accountId, isEmpty);

      final state =
          tester
              .withEvent(
                'account/one',
                const AccountOpened(accountId: 'one', name: 'Checking'),
                occuredAt: openedAt,
              )
              .run();

      expect(state.accountId, 'one');
      expect(state.name, 'Checking');
      expect(state.balance, 0);
      expect(state.transactionCount, 0);
      expect(state.openedAt, openedAt);
    });

    test('applies deposits, withdrawals, transfers, and renaming', () {
      final state =
          AggregateTester(AccountSummaryAggregate('one'))
              .withEvent(
                'account/one',
                const AccountOpened(accountId: 'one', name: 'Checking'),
                occuredAt: openedAt,
              )
              .withEvent(
                'account/one',
                const AccountAtmDeposited(accountId: 'one', amount: 100),
                occuredAt: depositedAt,
              )
              .withEvent(
                'account/one',
                const AccountAtmWithdrawn(accountId: 'one', amount: 20),
                occuredAt: withdrawnAt,
              )
              .withEvent(
                'account/one',
                const AccountInnerTransfer(
                  accountId: 'one',
                  fromAccountId: 'two',
                  amount: 15,
                ),
                occuredAt: transferredAt,
              )
              .withEvent(
                'account/one',
                const AccountRenamed(accountId: 'one', newName: 'Savings'),
                occuredAt: transferredAt,
              )
              .run();

      expect(state.name, 'Savings');
      expect(state.balance, 95);
      expect(state.transactionCount, 3);
      expect(state.lastTransactionAt, transferredAt);
    });

    test('skips events from another account', () {
      final state =
          AggregateTester(AccountSummaryAggregate('one'))
              .withEvent(
                'account/one',
                const AccountOpened(accountId: 'one', name: 'One'),
                occuredAt: openedAt,
              )
              .withEvent(
                'account/two',
                const AccountOpened(accountId: 'two', name: 'Two'),
                occuredAt: openedAt,
              )
              .withEvent(
                'account/two',
                const AccountAtmDeposited(accountId: 'two', amount: 500),
                occuredAt: depositedAt,
              )
              .run();

      expect(state.accountId, 'one');
      expect(state.name, 'One');
      expect(state.balance, 0);
      expect(state.transactionCount, 0);
    });
  });
}
