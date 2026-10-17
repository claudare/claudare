import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../paths.dart';

/// Expense transactions in account event order.
class AccountExpensesState implements AggregateState<AccountEvent> {
  final expenses = <AccountExpenseRecorded>[];

  @override
  void apply(EventEnvelope<AccountEvent> envelope) {
    final event = envelope.event;
    if (event is AccountExpenseRecorded) expenses.add(event);
  }
}

Aggregate<AccountEvent, AccountExpensesState> accountExpensesAggregate(
  String accountId,
) => Aggregate(
  name: 'Account expenses $accountId',
  filter: accountStreamFilter(accountId),
  state: AccountExpensesState(),
);
