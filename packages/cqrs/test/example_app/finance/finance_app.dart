import 'package:cqrs/cqrs.dart';

import 'command/atm_depost.dart';
import 'command/atm_withdrawal.dart';
import 'command/open_account.dart';
import 'command/rename_account.dart';
import 'command/transfer_funds_between_accounts.dart';
import 'account_event/account.dart';
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
    required AccountsSummaryReadModel accountSummaryRepo,
    required TotalBalanceReadModel totalBalanceRepo,
    int runtimeVersion = 1,
    MigrationPolicy migrationPolicy = MigrationPolicy.whenVersionChanges,
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
      runtimeName: 'finance-main',
      runtimeVersion: runtimeVersion,
      migrationPolicy: migrationPolicy,
      projectors: [accountSummaryProjection, totalBalanceProjection],
    );
    _cqrsRuntime
      ..registerEvent(const AccountAtmDepositedCodec())
      ..registerEvent(const AccountAtmWithdrawnCodec())
      ..registerEvent(const AccountInnerTransferCodec())
      ..registerEvent(const AccountOpenedCodec())
      ..registerEvent(const AccountRenamedCodec());

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
    // TODO: how to show progress? This could take a while.
    await _cqrsRuntime.initializeProjections();
  }

  Future<void> recreateProjections() => _cqrsRuntime.recreateProjections();
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
