import 'package:core/cqrs.dart';

import '../account_event/account.dart';
import '../stream_id/account_stream_id.dart';

class AtmDepositInput implements CommandInput {
  final String accountId;
  final int amount;

  const AtmDepositInput({required this.accountId, required this.amount});

  @override
  String get kind => 'atmDeposit';

  @override
  Map<String, dynamic> toJson() => {'accountId': accountId, 'amount': amount};
}

class AtmDeposit implements Command<AtmDepositInput> {
  @override
  Future<void> handle(input, ctx) async {
    if (input.amount <= 0) {
      return ctx.nack('amount must be positive');
    }

    final stream = ctx.stream(accountCodec, accountStreamId, input.accountId);

    await stream.mustExist();

    stream.append(AccountAtmDeposited(amount: input.amount));
  }
}
