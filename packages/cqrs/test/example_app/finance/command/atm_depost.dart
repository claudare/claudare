import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class AtmDepositInput {
  final String accountId;
  final int amount;

  const AtmDepositInput({required this.accountId, required this.amount});
}

class AtmDeposit implements Command<AtmDepositInput> {
  @override
  Future<void> handle(input, ctx) async {
    if (input.amount <= 0) {
      throw const CommandException('amount must be positive');
    }

    final stream = ctx.stream<AccountEvent>(
      accountStreamRoute.buildPath(input.accountId),
    );

    await stream.mustExist();

    stream.append(AccountAtmDeposited(amount: input.amount));
  }
}
