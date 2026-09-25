import 'package:cqrs/cqrs.dart';

import 'aggregate/account_list.dart';
import 'aggregate/account_list_snapshotter.dart';
import 'aggregate/account_summary.dart';
import 'aggregate/total_balance.dart';
import 'command/atm_depost.dart';
import 'command/atm_withdrawal.dart';
import 'command/open_account.dart';
import 'command/rename_account.dart';
import 'command/transfer_funds_between_accounts.dart';
import 'account_event/account.dart';

class FinanceApp {
  late final CqrsRuntime _cqrsRuntime;
  late final AccountListSnapshotter _accountListSnapshotter;

  late final Commands command;
  late final Queries query;

  FinanceApp({required CqrsRuntime cqrsRuntime}) {
    _cqrsRuntime = cqrsRuntime;

    _cqrsRuntime.eventRegistry
      ..add(const AccountAtmDepositedCodec())
      ..add(const AccountAtmWithdrawnCodec())
      ..add(const AccountInnerTransferCodec())
      ..add(const AccountOpenedCodec())
      ..add(const AccountRenamedCodec())
      ..freeze();

    _accountListSnapshotter = AccountListSnapshotter();

    command = Commands(_cqrsRuntime);
    query = Queries(_cqrsRuntime, _accountListSnapshotter);
  }
}

class Commands {
  final CqrsRuntime _runtime;

  const Commands(this._runtime);

  Future<void> atmDeposit({required String accountId, required int amount}) =>
      _runtime.execute(AtmDeposit(accountId: accountId, amount: amount));

  Future<void> atmWithdrawal({
    required String accountId,
    required int amount,
  }) => _runtime.execute(AtmWithdrawal(accountId: accountId, amount: amount));

  Future<void> openAccount({required String accountId, required String name}) =>
      _runtime.execute(OpenAccount(accountId: accountId, name: name));

  Future<void> renameAccount({
    required String accountId,
    required String newName,
  }) => _runtime.execute(RenameAccount(accountId: accountId, newName: newName));

  Future<void> transferFundsBetweenAccounts({
    required String fromAccountId,
    required String toAccountId,
    required int amount,
  }) => _runtime.execute(
    TransferFundsBetweenAccounts(
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amount: amount,
    ),
  );
}

class Queries {
  final CqrsRuntime _runtime;
  final AccountListSnapshotter _accountListSnapshotter;

  const Queries(this._runtime, this._accountListSnapshotter);

  Future<AccountSummaryState> accountSummary(String accountId) =>
      _runtime.resolve(AccountSummaryAggregate(accountId));

  Future<AccountListState> accountList() =>
      _runtime.resolve(AccountListAggregate(_accountListSnapshotter));

  Future<TotalBalanceState> totalBalance() =>
      _runtime.resolve(TotalBalanceAggregate());
}
