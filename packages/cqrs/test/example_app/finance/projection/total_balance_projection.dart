import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../paths.dart';

/// Totals balances across all account streams.
class TotalBalanceProjection
    implements Projection<TotalBalanceModel, AccountEvent> {
  @override
  String get name => 'total-balance';

  @override
  LogFilter get filter => allAccountsFilter;

  @override
  ProjectionLoad<TotalBalanceModel> load() =>
      ProjectionLoad.initial(TotalBalanceModel());

  @override
  void apply(TotalBalanceModel model, EventEnvelope<AccountEvent> envelope) {
    final amount = switch (envelope.event) {
      AccountAtmDeposited(:final amount) => amount,
      AccountAtmWithdrawn(:final amount) => -amount,
      AccountInnerTransfer(:final amount) => amount,
      AccountOpened() || AccountRenamed() => 0,
    };
    final id = accountIdFromStream(envelope.streamPath);
    model._accountBalances[id] = (model._accountBalances[id] ?? 0) + amount;
    model.balance += amount;
  }

  @override
  void onStreamDeleted(TotalBalanceModel model, StreamDeletion deletion) {
    final id = accountIdFromStream(deletion.streamPath);
    model.balance -= model._accountBalances.remove(id) ?? 0;
  }
}

/// Combined account balance.
class TotalBalanceModel {
  int balance = 0;
  final _accountBalances = <String, int>{};

  @override
  String toString() => 'TotalBalanceModel(balance: $balance)';
}
