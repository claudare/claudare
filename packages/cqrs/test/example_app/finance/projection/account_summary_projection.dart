import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../paths.dart';

/// Reconstructs the summary of one account.
class AccountSummaryProjection
    implements Projection<AccountSummaryModel, AccountEvent> {
  final String accountId;

  const AccountSummaryProjection(this.accountId);

  @override
  String get name => 'account-$accountId';

  @override
  LogFilter get filter => accountStreamFilter(accountId);

  @override
  ProjectionLoad<AccountSummaryModel> load() =>
      ProjectionLoad.initial(AccountSummaryModel());

  @override
  void apply(AccountSummaryModel model, EventEnvelope<AccountEvent> envelope) {
    final occuredAt = envelope.occuredAt;
    switch (envelope.event) {
      case AccountOpened(:final name):
        model.accountId = accountIdFromStream(envelope.streamPath);
        model.name = name;
        model.balance = 0;
        model.openedAt = occuredAt;
        model.transactionCount = 0;
      case AccountAtmDeposited(:final amount):
        model.balance += amount;
        model.lastTransactionAt = occuredAt;
        model.transactionCount++;
      case AccountAtmWithdrawn(:final amount):
        model.balance -= amount;
        model.lastTransactionAt = occuredAt;
        model.transactionCount++;
      case AccountInnerTransfer(:final amount):
        model.balance += amount;
        model.lastTransactionAt = occuredAt;
        model.transactionCount++;
      case AccountRenamed(:final newName):
        model.name = newName;
    }
  }

  @override
  void onStreamDeleted(AccountSummaryModel model, StreamDeletion deletion) {
    model.accountId = '';
    model.name = '';
    model.balance = 0;
    model.transactionCount = 0;
    model.openedAt = DateTime.fromMillisecondsSinceEpoch(0);
    model.lastTransactionAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// Current account details and transaction totals.
class AccountSummaryModel {
  String accountId = '';
  String name = '';
  int balance = 0;
  int transactionCount = 0;
  DateTime openedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastTransactionAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String toString() {
    return 'AccountSummaryModel(accountId: $accountId, name: $name, balance: $balance, transactionCount: $transactionCount, openedAt: $openedAt, lastTransactionAt: $lastTransactionAt)';
  }
}
