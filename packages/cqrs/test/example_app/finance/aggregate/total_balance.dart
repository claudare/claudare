import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class TotalBalanceState {
  int balance = 0;

  TotalBalanceState();

  @override
  String toString() {
    return 'TotalBalanceState(balance: $balance)';
  }
}

class TotalBalanceAggregate
    implements Aggregate<AccountEvent, TotalBalanceState> {
  @override
  final int version = 1;

  @override
  StreamRoute get streamRoute => accountStreamRoute;

  @override
  get snapshotter => null;

  @override
  TotalBalanceState initialState() {
    return TotalBalanceState();
  }

  @override
  bool canApply(EventEnvelope<AccountEvent> envelope) {
    return true;
  }

  @override
  void apply(TotalBalanceState state, EventEnvelope<AccountEvent> envelope) {
    final event = envelope.event;

    switch (event) {
      case AccountAtmDeposited(:final amount):
        state.balance += amount;
      case AccountAtmWithdrawn(:final amount):
        state.balance -= amount;
      case AccountOpened():
      case AccountInnerTransfer():
      case AccountRenamed():
        break;
    }
  }
}
