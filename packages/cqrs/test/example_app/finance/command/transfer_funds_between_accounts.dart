import 'dart:typed_data' show Uint8List;

import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class TransferFundsBetweenAccountsInput implements CommandInput {
  final String fromAccountId;
  final String toAccountId;
  final int amount;

  const TransferFundsBetweenAccountsInput({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
  });

  @override
  String get kind => 'TransferFundsBetweenAccounts';

  @override
  Uint8List encode() => JsonConverter.encode({
    'fromAccountId': fromAccountId,
    'toAccountId': toAccountId,
    'amount': amount,
  });
}

/// An example of using multiple streams + consistency check
class TransferFundsBetweenAccounts
    implements Command<TransferFundsBetweenAccountsInput> {
  @override
  Future<void> handle(input, ctx) async {
    if (input.amount <= 0) {
      throw const CommandException('amount must be positive');
    }

    final fromStream = ctx.stream(
      accountCodec,
      accountStreamRoute,
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
      throw const CommandException('insufficient funds');
    }

    fromStream.append(
      AccountInnerTransfer(
        fromAccountId: input.toAccountId,
        amount: -input.amount,
      ),
    );

    final toStream = ctx.stream(
      accountCodec,
      accountStreamRoute,
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
