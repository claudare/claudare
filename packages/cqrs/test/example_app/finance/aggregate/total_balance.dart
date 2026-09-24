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
    implements Aggregate<AccountEvent, String, TotalBalanceState> {
  @override
  final int version = 1;

  @override
  StreamRoute<String> get streamRoute => accountStreamRoute;

  @override
  get snapshotter => null;

  @override
  TotalBalanceState initialState() {
    return TotalBalanceState();
  }

  @override
  bool canApply(EventEnvelope<AccountEvent, String> envelope) {
    return true;
  }

  @override
  void apply(
    TotalBalanceState state,
    EventEnvelope<AccountEvent, String> envelope,
  ) {
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
