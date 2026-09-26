import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class AccountSummaryState implements AggregateState<AccountEvent> {
  String accountId = '';
  String name = '';
  int balance = 0;
  int transactionCount = 0;
  DateTime openedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastTransactionAt = DateTime.fromMillisecondsSinceEpoch(0);

  AccountSummaryState();

  @override
  String toString() {
    return 'AccountSummaryState(accountId: $accountId, name: $name, balance: $balance, transactionCount: $transactionCount, openedAt: $openedAt, lastTransactionAt: $lastTransactionAt)';
  }

  @override
  void apply(EventEnvelope<AccountEvent> envelope) {
    final event = envelope.event;
    final occuredAt = envelope.occuredAt;
    switch (event) {
      case AccountOpened(:final name, :final accountId):
        this.accountId = accountId;
        this.name = name;
        balance = 0;
        openedAt = occuredAt;
        transactionCount = 0;
      case AccountAtmDeposited(:final amount):
        balance += amount;
        lastTransactionAt = occuredAt;
        transactionCount++;
      case AccountAtmWithdrawn(:final amount):
        balance -= amount;
        lastTransactionAt = occuredAt;
        transactionCount++;
      case AccountInnerTransfer(:final amount):
        balance += amount;
        lastTransactionAt = occuredAt;
        transactionCount++;
      case AccountRenamed(:final newName):
        name = newName;
    }
  }
}

Aggregate<AccountEvent, AccountSummaryState> accountSummaryAggregate(
  String accountId,
) => Aggregate(
  name: 'Account $accountId',
  filter: PatternFilter.exact(accountStreamRoute.buildPath(accountId)),
  state: AccountSummaryState(),
);
