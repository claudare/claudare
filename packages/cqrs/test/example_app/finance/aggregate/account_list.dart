import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';
import 'account_list_snapshotter.dart';
import 'account_summary.dart';

enum SortDirection { ascending, descending }

class AccountListState implements SnapshotCloneable<AccountListState> {
  final accounts = <String, AccountSummaryState>{};

  AccountListState();

  List<AccountSummaryState> toSortedByName({
    SortDirection direction = SortDirection.ascending,
  }) {
    final list = accounts.values.toList();
    if (direction == SortDirection.ascending) {
      list.sort((a, b) => a.name.compareTo(b.name));
    } else {
      list.sort((a, b) => b.name.compareTo(a.name));
    }
    return list;
  }

  List<AccountSummaryState> toSortedByBalance({
    SortDirection direction = SortDirection.ascending,
  }) {
    final list = accounts.values.toList();
    if (direction == SortDirection.ascending) {
      list.sort((a, b) => a.balance.compareTo(b.balance));
    } else {
      list.sort((a, b) => b.balance.compareTo(a.balance));
    }
    return list;
  }

  @override
  AccountListState clone() {
    final copy = AccountListState();
    for (final entry in accounts.entries) {
      copy.accounts[entry.key] = entry.value.clone();
    }
    return copy;
  }
}

class AccountListAggregate
    implements Aggregate<AccountEvent, String, AccountListState> {
  final AccountListSnapshotter? _snapshotter;
  AccountListAggregate([this._snapshotter]);

  @override
  AccountListSnapshotter? get snapshotter => _snapshotter;

  @override
  final int version = 1;

  @override
  StreamRoute<String> get streamRoute => accountStreamRoute;

  @override
  AccountListState initialState() {
    return AccountListState();
  }

  @override
  bool canApply(_) {
    return true;
  }

  @override
  void apply(
    AccountListState state,
    EventEnvelope<AccountEvent, String> envelope,
  ) {
    final accountId = envelope.streamParams;

    final thisAggregate = AccountSummaryAggregate(accountId);
    final thisState = state.accounts[accountId] ?? thisAggregate.initialState();
    thisAggregate.apply(thisState, envelope);

    state.accounts[accountId] = thisState;
  }
}
