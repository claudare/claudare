import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class AccountSummaryState {
  String accountId = '';
  String name = '';
  int balance = 0;
  int transactionCount = 0;
  DateTime openedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastTransactionAt = DateTime.fromMillisecondsSinceEpoch(0);

  AccountSummaryState();

  AccountSummaryState.withInitialValue({
    required this.accountId,
    required this.name,
    required this.openedAt,
  });

  AccountSummaryState clone() =>
      AccountSummaryState()
        ..accountId = accountId
        ..name = name
        ..balance = balance
        ..transactionCount = transactionCount
        ..openedAt = openedAt
        ..lastTransactionAt = lastTransactionAt;

  @override
  String toString() {
    return 'AccountSummaryState(accountId: $accountId, name: $name, balance: $balance, transactionCount: $transactionCount, openedAt: $openedAt, lastTransactionAt: $lastTransactionAt)';
  }
}

class AccountSummaryAggregate
    implements Aggregate<AccountEvent, String, AccountSummaryState> {
  final String accountId;

  AccountSummaryAggregate(this.accountId);

  @override
  Snapshotter<AccountSummaryState>? get snapshotter => null;

  @override
  final int version = 1;

  @override
  StreamRoute<String> get streamRoute => accountStreamRoute;

  @override
  AccountSummaryState initialState() {
    return AccountSummaryState();
  }

  @override
  bool canApply(EventEnvelope<AccountEvent, String> envelope) {
    return envelope.streamParams == accountId;
  }

  @override
  void apply(
    AccountSummaryState state,
    EventEnvelope<AccountEvent, String> envelope,
  ) {
    final event = envelope.event;
    final occuredAt = envelope.occuredAt;
    switch (event) {
      case AccountOpened(:final name):
        state.accountId = accountId;
        state.name = name;
        state.balance = 0;
        state.openedAt = occuredAt;
        state.transactionCount = 0;
      case AccountAtmDeposited(:final amount):
        state.balance += amount;
        state.lastTransactionAt = occuredAt;
        state.transactionCount++;
      case AccountAtmWithdrawn(:final amount):
        state.balance -= amount;
        state.lastTransactionAt = occuredAt;
        state.transactionCount++;
      case AccountInnerTransfer(:final amount):
        state.balance += amount;
        state.lastTransactionAt = occuredAt;
        state.transactionCount++;
      case AccountRenamed(:final newName):
        state.name = newName;
    }
  }
}
