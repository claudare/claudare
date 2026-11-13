import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../paths.dart';
import 'account_summary_projection.dart';

enum SortDirection { ascending, descending }

/// Collects summaries from every account stream.
class AccountListProjection
    implements Projection<AccountListModel, AccountEvent> {
  @override
  String get name => 'account-list';

  @override
  LogFilter get filter => allAccountsFilter;

  @override
  ProjectionLoad<AccountListModel> load() =>
      ProjectionLoad.initial(AccountListModel());

  @override
  void apply(AccountListModel model, EventEnvelope<AccountEvent> envelope) {
    final accountId = accountIdFromStream(envelope.streamPath);
    final projection = AccountSummaryProjection(accountId);
    final account = model.accounts.putIfAbsent(
      accountId,
      () => projection.load().model,
    );
    projection.apply(account, envelope);
  }

  @override
  void onStreamDeleted(AccountListModel model, StreamDeletion deletion) {
    model.accounts.remove(accountIdFromStream(deletion.streamPath));
  }
}

/// Account summaries with name and balance ordering.
class AccountListModel {
  final accounts = <String, AccountSummaryModel>{};

  List<AccountSummaryModel> toSortedByName({
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

  List<AccountSummaryModel> toSortedByBalance({
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
}
