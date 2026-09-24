import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

import '../../account_event/account.dart';
import '../../aggregate/account_list.dart';

void main() {
  final openedAt = DateTime.utc(2026, 1, 1);
  final depositedAt = DateTime.utc(2026, 1, 2);
  final renamedAt = DateTime.utc(2026, 1, 3);

  group('AccountListAggregate', () {
    late AccountListState state;

    setUp(() {
      state =
          AggregateTester(AccountListAggregate())
              .withEvent(
                'account/one',
                const AccountOpened(name: 'Zeta'),
                occuredAt: openedAt,
              )
              .withEvent(
                'account/two',
                const AccountOpened(name: 'Alpha'),
                occuredAt: openedAt,
              )
              .withEvent(
                'account/one',
                const AccountAtmDeposited(amount: 10),
                occuredAt: depositedAt,
              )
              .withEvent(
                'account/two',
                const AccountAtmDeposited(amount: 30),
                occuredAt: depositedAt,
              )
              .withEvent(
                'account/one',
                const AccountRenamed(newName: 'Beta'),
                occuredAt: renamedAt,
              )
              .run();
    });

    test('collects account streams', () {
      expect(state.accounts.keys, containsAll(['one', 'two']));
      expect(state.accounts['one']!.name, 'Beta');
      expect(state.accounts['two']!.balance, 30);
    });

    test('sorts by name in either direction', () {
      expect(state.toSortedByName().map((account) => account.accountId), [
        'two',
        'one',
      ]);
      expect(
        state
            .toSortedByName(direction: SortDirection.descending)
            .map((account) => account.accountId),
        ['one', 'two'],
      );
    });

    test('sorts by balance in either direction', () {
      expect(state.toSortedByBalance().map((account) => account.accountId), [
        'one',
        'two',
      ]);
      expect(
        state
            .toSortedByBalance(direction: SortDirection.descending)
            .map((account) => account.accountId),
        ['two', 'one'],
      );
    });
  });
}
