import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';
import 'account_summary.dart';

enum SortDirection { ascending, descending }

class AccountListState implements AggregateState<AccountEvent> {
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
  void apply(EventEnvelope<AccountEvent> envelope) {
    final accountId = envelope.event.accountId;
    final account = accounts.putIfAbsent(accountId, AccountSummaryState.new);
    account.apply(envelope);
  }
}

Aggregate<AccountEvent, AccountListState> accountListAggregate() => Aggregate(
  name: 'Account list',
  filter: accountStreamRoute.filter,
  state: AccountListState(),
);
