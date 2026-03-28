import 'dart:convert';

import 'package:core/src/cqrs.dart';

import '../account_event/account.dart';
import '../stream_id/account_stream_id.dart';

class TransferFundsBetweenAccountsInput implements CommandInput {
  final String fromAccountId;
  final String toAccountId;
  final int amount;

  TransferFundsBetweenAccountsInput({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
  }) : assert(amount > 0);

  @override
  String get kind => 'TransferFundsBetweenAccounts';

  @override
  Map<String, dynamic> toJson() => {
    'fromAccountId': fromAccountId,
    'toAccountId': toAccountId,
    'amount': amount,
  };
}

/// An example of using multiple streams + consistency check
class TransferFundsBetweenAccounts
    implements Command<TransferFundsBetweenAccountsInput> {
  @override
  Future<void> handle(input, ctx) async {
    final fromStream = ctx.stream(
      accountCodec,
      accountStreamId,
      input.fromAccountId,
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

    final newFromBalance = fromBalance - input.amount;

    if (newFromBalance < 0) {
      return ctx.nack('insufficient funds');
    }

    fromStream.append(
      AccountInnerTransfer(
        fromAccountId: input.toAccountId,
        amount: -input.amount,
      ),
    );

    final toStream = ctx.stream(
      accountCodec,
      accountStreamId,
      input.toAccountId,
    );

    await toStream.mustExist();

    toStream.append(
      AccountInnerTransfer(
        fromAccountId: input.fromAccountId,
        amount: input.amount,
      ),
    );
  }
}
