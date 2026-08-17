import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

import '../account_event/account.dart';
import '../read_model/accounts_summary_read_model.dart';
import '../projection/account_summary.dart';

DateTime _occuredAt = DateTime(0);

void main() {
  group('Account summary projection', () {
    late AccountsSummaryReadModel model;
    late AccountSummaryProjection projection;
    late ProjectionTester tester;

    setUp(() {
      model = AccountsSummaryReadModel();
      projection = AccountSummaryProjection(model);
      tester = ProjectionTester(projection);

      expect(model.isInitialized, false);
    });

    test('initializes', () async {
      final ok = await tester.run();

      expect(model.isInitialized, true);
      expect(ok, true);
      expect(tester.projection.failureHandler.hasErrored(), false);
    });

    test('applies all events', () async {
      final ok =
          await tester
              .withEvent(
                'account/1',
                AccountOpened(name: 'first'),
                occuredAt: _occuredAt,
              )
              .withEvent(
                'account/1',
                AccountAtmDeposited(amount: 40),
                occuredAt: _occuredAt,
              )
              .withEvent(
                'account/2',
                AccountOpened(name: 'second'),
                occuredAt: _occuredAt,
              )
              .withEvent(
                'account/2',
                AccountRenamed(newName: 'second-renamed'),
                occuredAt: _occuredAt,
              )
              .run();

      expect(model.isInitialized, true);

      expect(ok, true);
      expect(projection.failureHandler.hasErrored(), false);

      final accounts = await model.getAllSortedByNameDesc();

      expect(accounts.length, 2);

      expect(accounts[0].name, 'first');
      expect(accounts[1].name, 'second-renamed');

      expect(accounts[0].balance, 40);
      expect(accounts[1].balance, 0);
    });

    test('handles errors', () async {
      final ok =
          await tester
              .withEvent(
                'account/1',
                AccountAtmDeposited(amount: 9001),
                occuredAt: _occuredAt,
              )
              .run();

      expect(model.isInitialized, true);

      expect(ok, false);
      expect(projection.failureHandler.hasErrored(), true);
      // TODO: this needs improvement for sure
      final stdError =
          (projection.failureHandler as StandardProjectionFailureHandler)
              .error!;
      expect(stdError.error.toString(), 'Exception: invalid getAndStore id');
    });
  });
}
