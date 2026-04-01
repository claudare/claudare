import 'package:core/cqrs.dart';

import '../account_event/account.dart';
import '../stream_id/account_stream_id.dart';

class AtmWithdrawalInput implements CommandInput {
  final String accountId;
  final int amount;

  AtmWithdrawalInput({required this.accountId, required this.amount})
    : assert(amount > 0);

  @override
  String get kind => 'atmWithdrawal';

  @override
  Map<String, dynamic> toJson() => {'accountId': accountId, 'amount': amount};
}

class AtmWithdrawal implements Command<AtmWithdrawalInput> {
  @override
  Future<void> handle(input, ctx) async {
    final stream = ctx.stream(accountCodec, accountStreamId, input.accountId);

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

    final newBalance = balance - input.amount;

    if (newBalance < 0) {
      return ctx.nack('insufficient funds');
    }

    stream.append(AccountAtmWithdrawn(amount: input.amount));
  }
}
