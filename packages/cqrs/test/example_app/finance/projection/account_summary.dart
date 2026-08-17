import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../read_model/accounts_summary_read_model.dart';
import '../stream_route/account_stream_route.dart';

class AccountSummaryProjection implements Projection<AccountEvent, String> {
  final AccountsSummaryReadModel _repo;
  final _failureHandler = StandardProjectionFailureHandler();

  AccountSummaryProjection(this._repo);

  @override
  String get name => 'account-summary';

  @override
  final int version = 1;

  @override
  StreamRoute<String> get streamRoute => accountStreamRoute;

  @override
  ProjectionFailureHandler get failureHandler => _failureHandler;

  @override
  Future<void> reset() => _repo.reset();

  @override
  void onBatchApplied() {}

  @override
  Future<void> apply(
    String accountId,
    AccountEvent event,
    EventMetadata metadata,
  ) {
    switch (event) {
      case AccountOpened(:final name):
        return _repo.store(
          accountId,
          AccountSummary(
            accountId: accountId,
            name: name,
            balance: 0,
            openedAt: metadata.occuredAt,
            lastTransactionAt: metadata.occuredAt,
            transactionCount: 0,
          ),
        );
      case AccountAtmDeposited(:final amount):
        return _repo.getAndStore(
          accountId,
          (summary) => summary.copyWith(
            balance: summary.balance + amount,
            lastTransactionAt: metadata.occuredAt,
            transactionCount: summary.transactionCount + 1,
          ),
        );
      case AccountAtmWithdrawn(:final amount):
        return _repo.getAndStore(
          accountId,
          (summary) => summary.copyWith(
            balance: summary.balance - amount,
            lastTransactionAt: metadata.occuredAt,
            transactionCount: summary.transactionCount + 1,
          ),
        );
      case AccountInnerTransfer(:final amount):
        return _repo.getAndStore(
          accountId,
          (summary) => summary.copyWith(
            balance: summary.balance + amount,
            lastTransactionAt: metadata.occuredAt,
            transactionCount: summary.transactionCount + 1,
          ),
        );
      case AccountRenamed(:final newName):
        return _repo.getAndStore(
          accountId,
          (summary) => summary.copyWith(name: newName),
        );
    }
  }
}
