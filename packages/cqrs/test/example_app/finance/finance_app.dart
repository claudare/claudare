import 'package:cqrs/cqrs.dart';

import 'aggregate/account_list.dart';
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

  late final Commands command;
  late final ReadModels readModels;

  FinanceApp({required CqrsRuntimeDependencies dependencies}) {
    final eventRegistry =
        EventRegistry()
          ..add(const AccountAtmDepositedCodec())
          ..add(const AccountAtmWithdrawnCodec())
          ..add(const AccountInnerTransferCodec())
          ..add(const AccountOpenedCodec())
          ..add(const AccountRenamedCodec());

    _cqrsRuntime = CqrsRuntime(
      dependencies: dependencies,
      eventRegistry: eventRegistry,
      runtimeName: 'finance-main',
    );

    command = Commands(_cqrsRuntime);
    readModels = ReadModels(_cqrsRuntime);
  }

  Future<void> init() async {
    // TODO: how to show progress? This could take a while.
    await _cqrsRuntime.initialize();
  }

  Future<void> close() => _cqrsRuntime.close();
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

class ReadModels {
  final CqrsRuntime _runtime;

  const ReadModels(this._runtime);

  Future<AccountSummaryState> accountSummary(String accountId) =>
      _runtime.resolve(AccountSummaryAggregate(accountId), accountId);

  Future<AccountListState> accountList() =>
      _runtime.resolve(AccountListAggregate(), '');

  Future<TotalBalanceState> totalBalance() =>
      _runtime.resolve(TotalBalanceAggregate(), '');
}
