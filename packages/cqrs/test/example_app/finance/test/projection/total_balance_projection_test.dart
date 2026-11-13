import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

import '../../account_event/account.dart';
import '../../projection/total_balance_projection.dart';

void main() {
  final openedAt = DateTime.utc(2026, 1, 1);
  final depositedAt = DateTime.utc(2026, 1, 2);
  final withdrawnAt = DateTime.utc(2026, 1, 3);
  final transferredAt = DateTime.utc(2026, 1, 4);

  group('TotalBalanceProjection', () {
    test('starts at zero', () async {
      final state = await ProjectionTester(TotalBalanceProjection()).run();

      expect(state.balance, 0);
    });

    test('sums deposits and withdrawals across account streams', () async {
      final state = await ProjectionTester(TotalBalanceProjection())
          .withEvent(
            'account/one',
            const AccountAtmDeposited(amount: 100),
            occuredAt: depositedAt,
          )
          .withEvent(
            'account/two',
            const AccountAtmDeposited(amount: 50),
            occuredAt: depositedAt,
          )
          .withEvent(
            'account/one',
            const AccountAtmWithdrawn(amount: 10),
            occuredAt: withdrawnAt,
          )
          .run();

      expect(state.balance, 140);
    });

    test('ignores account metadata and internal transfers', () async {
      final state = await ProjectionTester(TotalBalanceProjection())
          .withEvent(
            'account/one',
            const AccountAtmDeposited(amount: 25),
            occuredAt: depositedAt,
          )
          .withEvent(
            'account/two',
            const AccountOpened(name: 'Two'),
            occuredAt: openedAt,
          )
          .withEvent(
            'account/one',
            const AccountInnerTransfer(otherAccountId: 'two', amount: -5),
            occuredAt: transferredAt,
          )
          .withEvent(
            'account/two',
            const AccountInnerTransfer(otherAccountId: 'one', amount: 5),
            occuredAt: transferredAt,
          )
          .withEvent(
            'account/one',
            const AccountRenamed(newName: 'Renamed'),
            occuredAt: transferredAt,
          )
          .run();

      expect(state.balance, 25);
    });
  });
}
