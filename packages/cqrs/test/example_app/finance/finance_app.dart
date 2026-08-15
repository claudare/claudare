import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';

import 'command/atm_depost.dart';
import 'command/atm_withdrawal.dart';
import 'command/open_account.dart';
import 'command/rename_account.dart';
import 'command/transfer_funds_between_accounts.dart';
import 'projection/account_summary.dart';
import 'projection/total_balance.dart';
import 'read_model/accounts_summary_read_model.dart';
import 'read_model/total_balance_read_model.dart';

class FinanceApp {
  late final CqrsRuntime _cqrsRuntime;

  late final ReadModels readModel;
  late final Commands command;

  FinanceApp({
    required CqrsRuntimeDependencies dependencies,
    required DeviceId deviceId,
    required AccountsSummaryReadModel accountSummaryRepo,
    required TotalBalanceReadModel totalBalanceRepo,
  }) {
    final accountSummaryProjection = AccountSummaryProjection(
      accountSummaryRepo,
    );
    final totalBalanceProjection = TotalBalanceProjection(totalBalanceRepo);

    readModel = ReadModels(
      accountsSummary: accountSummaryRepo,
      totalBalance: totalBalanceRepo,
    );

    _cqrsRuntime = CqrsRuntime(
      dependencies: dependencies,
      thisDeviceId: deviceId,
      runtimeName: 'finance-main',
      runtimeVersion: 1,
      projectors: [accountSummaryProjection, totalBalanceProjection],
    );

    command = Commands(
      atmDeposit: _cqrsRuntime.bindCommand(AtmDeposit(), [
        accountSummaryProjection,
      ]),
      atmWithdrawal: _cqrsRuntime.bindCommand(AtmWithdrawal(), [
        accountSummaryProjection,
      ]),
      openAccount: _cqrsRuntime.bindCommand(OpenAccount(), [
        accountSummaryProjection,
      ]),
      renameAccount: _cqrsRuntime.bindCommand(RenameAccount(), [
        accountSummaryProjection,
      ]),
      transferFundsBetweenAccounts: _cqrsRuntime.bindCommand(
        TransferFundsBetweenAccounts(),
        [accountSummaryProjection],
      ),
    );
  }

  Future<void> init() async {
    // TODO: should the deviceId be loaded here and set on the runtime?
    // TODO: how to show progress? This could take a while.

    await _cqrsRuntime.initializeProjections();
  }
}

class Commands {
  final BoundCommand<AtmDepositInput> atmDeposit;
  final BoundCommand<AtmWithdrawalInput> atmWithdrawal;
  final BoundCommand<OpenAccountInput> openAccount;
  final BoundCommand<RenameAccountInput> renameAccount;
  final BoundCommand<TransferFundsBetweenAccountsInput>
  transferFundsBetweenAccounts;

  const Commands({
    required this.atmDeposit,
    required this.atmWithdrawal,
    required this.openAccount,
    required this.renameAccount,
    required this.transferFundsBetweenAccounts,
  });
}

class ReadModels {
  final AccountsSummaryReadModel accountsSummary;
  final TotalBalanceReadModel totalBalance;

  const ReadModels({required this.accountsSummary, required this.totalBalance});
}
