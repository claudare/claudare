import 'package:core/cqrs_test_utils.dart';
import 'package:test/test.dart';

import '../account_event/account.dart';
import '../read_model/accounts_summary_read_model.dart';
import '../projection/account_summary.dart';

void main() {
  group('Account summary projection', () {
    late AccountsSummaryReadModel model;
    late AccountSummaryProjection projection;
    late ProjectionTester<AccountEvent, String> tester;

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
      expect(tester.failureState.hasError, false);
    });

    test('applies all events', () async {
      final ok =
          await tester
              .withEvent("1", AccountOpened(name: "first"))
              .withEvent("1", AccountAtmDeposited(amount: 40))
              .withEvent("2", AccountOpened(name: "second"))
              .withEvent("2", AccountRenamed(newName: "second-renamed"))
              .run();

      expect(model.isInitialized, true);

      expect(ok, true);
      expect(tester.failureState.hasError, false);

      final accounts = await model.getAllSortedByNameDesc();

      expect(accounts.length, 2);

      expect(accounts[0].name, "first");
      expect(accounts[1].name, "second-renamed");

      expect(accounts[0].balance, 40);
      expect(accounts[1].balance, 0);
    });

    test('handles errors', () async {
      final ok =
          await tester.withEvent("1", AccountAtmDeposited(amount: 9001)).run();

      expect(model.isInitialized, true);

      expect(ok, false);
      expect(tester.failureState.hasError, true);
      // TODO: this is a bad user experience for sure
      expect(tester.failureState.message, "Exception: invalid getAndStore id");
    });
  });
}
