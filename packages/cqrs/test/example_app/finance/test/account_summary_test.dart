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
      await tester.run();

      expect(model.isInitialized, true);
    });

    test('applies all events', () async {
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

      final accounts = await model.getAllSortedByNameDesc();

      expect(accounts.length, 2);

      expect(accounts[0].name, 'first');
      expect(accounts[1].name, 'second-renamed');

      expect(accounts[0].balance, 40);
      expect(accounts[1].balance, 0);
    });

    test('handles errors', () async {
      await expectLater(
        tester
            .withEvent(
              'account/1',
              AccountAtmDeposited(amount: 9001),
              occuredAt: _occuredAt,
            )
            .run(),
        throwsA(isA<Exception>()),
      );

      expect(model.isInitialized, true);
    });
  });
}
