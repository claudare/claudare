import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class AtmDepositInput implements CommandInput {
  final String accountId;
  final int amount;

  const AtmDepositInput({required this.accountId, required this.amount});

  @override
  String get kind => 'atmDeposit';

  @override
  encode() => JsonConverter.encode({'accountId': accountId, 'amount': amount});
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
