import 'package:core/cqrs.dart';
import 'package:core/src/device_id.dart';

import 'command/atm_depost.dart';
import 'command/atm_withdrawal.dart';
import 'command/open_account.dart';
import 'command/rename_account.dart';
import 'command/transfer_funds_between_accounts.dart';
import 'projection/account_summary.dart';
import 'read_model/accounts_summary_read_model.dart';

class FinanceApp {
  late final CqrsRuntime _cqrsRuntime;

  late final ReadModels readModel;
  late final Commands command;

  FinanceApp({
    required CqrsRuntimeConfig config,
    required DeviceId deviceId,
    required AccountsSummaryReadModel accountSummaryRepo,
  }) {
    final accountSummaryProjection = AccountSummaryProjection(
      accountSummaryRepo,
    );

    readModel = ReadModels(accountsSummary: accountSummaryRepo);

    _cqrsRuntime = CqrsRuntime(
      config: config,
      thisDeviceId: deviceId,
      runtimeName: 'finance-main',
      projectors: [accountSummaryProjection],
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

    await _cqrsRuntime.catchupAllProjections(1);
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

  const ReadModels({required this.accountsSummary});
}
