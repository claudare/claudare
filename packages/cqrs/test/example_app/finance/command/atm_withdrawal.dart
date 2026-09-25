import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class AtmWithdrawal implements Command {
  final String accountId;
  final int amount;

  const AtmWithdrawal({required this.accountId, required this.amount});

  @override
  Future<void> handle(ctx) async {
    if (amount <= 0) {
      throw const CommandException('amount must be positive');
    }

    final stream = ctx.stream<AccountEvent>(
      accountStreamRoute.buildPath(accountId),
    );

    int balance = 0;

    final events = stream.scan();

    await for (final event in events) {
      // use pattern matching here
      switch (event) {
        case AccountAtmDeposited():
          balance += event.amount;
          break;
        case AccountAtmWithdrawn():
          balance -= event.amount;
          break;
        case AccountInnerTransfer():
          balance += event.amount;
          break;
        default:
          break;
      }
    }

    final newBalance = balance - amount;

    if (newBalance < 0) {
      throw const CommandException('insufficient funds');
    }

    stream.append(AccountAtmWithdrawn(amount: amount));
  }
}
