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

  Future<void> atmDeposit(AtmDepositInput input) =>
      _runtime.execute(AtmDeposit(), input);

  Future<void> atmWithdrawal(AtmWithdrawalInput input) =>
      _runtime.execute(AtmWithdrawal(), input);

  Future<void> openAccount(OpenAccountInput input) =>
      _runtime.execute(OpenAccount(), input);

  Future<void> renameAccount(RenameAccountInput input) =>
      _runtime.execute(RenameAccount(), input);

  Future<void> transferFundsBetweenAccounts(
    TransferFundsBetweenAccountsInput input,
  ) => _runtime.execute(TransferFundsBetweenAccounts(), input);
}

class Queries {
  final CqrsRuntime _runtime;
  final AccountListSnapshotter _accountListSnapshotter;

  const Queries(this._runtime, this._accountListSnapshotter);

  Future<AccountSummaryState> accountSummary(String accountId) =>
      _runtime.resolve(AccountSummaryAggregate(accountId), accountId);

  Future<AccountListState> accountList() =>
      _runtime.resolve(AccountListAggregate(_accountListSnapshotter), '');

  Future<TotalBalanceState> totalBalance() =>
      _runtime.resolve(TotalBalanceAggregate(), '');
}
