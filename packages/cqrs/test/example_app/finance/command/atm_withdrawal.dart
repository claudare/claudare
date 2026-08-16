import 'dart:typed_data' show Uint8List;

import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class AtmWithdrawalInput implements CommandInput {
  final String accountId;
  final int amount;

  const AtmWithdrawalInput({required this.accountId, required this.amount});

  @override
  String get kind => 'atmWithdrawal';

  @override
  Uint8List encode() =>
      JsonConverter.encode({'accountId': accountId, 'amount': amount});
}

class AtmWithdrawal implements Command<AtmWithdrawalInput> {
  @override
  Future<void> handle(input, ctx) async {
    if (input.amount <= 0) {
      throw const CommandException('amount must be positive');
    }

    final stream = ctx.stream(
      accountCodec,
      accountStreamRoute,
      input.accountId,
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

    final newBalance = balance - input.amount;

    if (newBalance < 0) {
      throw const CommandException('insufficient funds');
    }

    stream.append(AccountAtmWithdrawn(amount: input.amount));
  }
}
