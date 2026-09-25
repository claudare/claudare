import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

/// An example of using multiple streams + consistency check
class TransferFundsBetweenAccounts implements Command {
  final String fromAccountId;
  final String toAccountId;
  final int amount;

  const TransferFundsBetweenAccounts({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
  });

  @override
  Future<void> handle(ctx) async {
    if (amount <= 0) {
      throw const CommandException('amount must be positive');
    }

    final fromStream = ctx.stream<AccountEvent>(
      accountStreamRoute.buildPath(fromAccountId),
    );

    final scanner = fromStream.scan();

    final fromBalance = await scanner.fold(0, (prev, event) {
      switch (event) {
        case AccountAtmDeposited():
          return prev + event.amount;
        case AccountAtmWithdrawn():
          return prev - event.amount;
        case AccountInnerTransfer():
          return prev + event.amount;
        // TODO: new events could be missed here
        default:
          return prev;
      }
    });

    final newFromBalance = fromBalance - amount;

    if (newFromBalance < 0) {
      throw const CommandException('insufficient funds');
    }

    fromStream.append(
      AccountInnerTransfer(
        accountId: fromAccountId,
        fromAccountId: toAccountId,
        amount: -amount,
      ),
    );

    final toStream = ctx.stream<AccountEvent>(
      accountStreamRoute.buildPath(toAccountId),
    );

    await toStream.mustExist();

    toStream.append(
      AccountInnerTransfer(
        accountId: toAccountId,
        fromAccountId: fromAccountId,
        amount: amount,
      ),
    );
  }
}
