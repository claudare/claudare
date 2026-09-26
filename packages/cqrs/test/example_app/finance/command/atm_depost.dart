import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../paths.dart';

class AtmDeposit implements Command {
  final String accountId;
  final int amount;

  const AtmDeposit({required this.accountId, required this.amount});

  @override
  Future<void> handle(ctx) async {
    if (amount <= 0) {
      throw const CommandException('amount must be positive');
    }

    final stream = ctx.stream<AccountEvent>(accountStream(accountId));

    await stream.mustExist();

    stream.append(AccountAtmDeposited(accountId: accountId, amount: amount));
  }
}
