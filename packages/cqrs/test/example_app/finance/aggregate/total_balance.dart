import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../paths.dart';

class TotalBalanceState implements AggregateState<AccountEvent> {
  int balance = 0;

  TotalBalanceState();

  @override
  String toString() {
    return 'TotalBalanceState(balance: $balance)';
  }

  @override
  void apply(EventEnvelope<AccountEvent> envelope) {
    final event = envelope.event;

    switch (event) {
      case AccountAtmDeposited(:final amount):
        balance += amount;
      case AccountAtmWithdrawn(:final amount):
        balance -= amount;
      case AccountOpened():
      case AccountInnerTransfer():
      case AccountRenamed():
        break;
    }
  }
}

Aggregate<AccountEvent, TotalBalanceState> totalBalanceAggregate() => Aggregate(
  name: 'Total balance',
  filter: allAccountsFilter,
  state: TotalBalanceState(),
);
