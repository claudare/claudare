import 'package:core/src/cqrs.dart';

import '../account_event/account.dart';
import '../stream_id/account_stream_id.dart';

class AtmDepositInput implements CommandInput {
  final String accountId;
  final int amount;

  AtmDepositInput({required this.accountId, required this.amount})
    : assert(amount > 0);

  @override
  String get kind => 'atmDeposit';

  @override
  Map<String, dynamic> toJson() => {'accountId': accountId, 'amount': amount};
}

class AtmDeposit implements Command<AtmDepositInput> {
  @override
  Future<void> handle(input, ctx) async {
    final stream = ctx.stream(accountCodec, accountStreamId, input.accountId);

    stream.lockLatest();

    stream.append(AccountAtmDeposited(amount: input.amount));
  }
}
