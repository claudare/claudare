import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../paths.dart';

class TotalBalanceState implements AggregateState<AccountEvent> {
  int balance = 0;
  final _accountBalances = <String, int>{};

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
        _applyBalanceChange(event.accountId, amount);
      case AccountAtmWithdrawn(:final amount):
        _applyBalanceChange(event.accountId, -amount);
      case AccountOpened():
        break;
      case AccountInnerTransfer(:final amount):
        _applyBalanceChange(event.accountId, amount);
      case AccountRenamed():
        break;
    }
  }

  // In a real application, accounts will never be deleted,
  // but for the sake of example...
  @override
  void onStreamDeleted(StreamDeletion deletion) {
    final accountId = accountIdFromStream(deletion.streamPath);
    balance -= _accountBalances.remove(accountId) ?? 0;
  }

  void _applyBalanceChange(String accountId, int amount) {
    _accountBalances[accountId] = (_accountBalances[accountId] ?? 0) + amount;
    balance += amount;
  }
}

Aggregate<AccountEvent, TotalBalanceState> totalBalanceAggregate() => Aggregate(
  name: 'Total balance',
  filter: allAccountsFilter,
  state: TotalBalanceState(),
);
