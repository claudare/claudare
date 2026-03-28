import 'dart:convert';

import 'package:core/src/cqrs.dart';

import '../account_event/account.dart';
import '../stream_id/account_stream_id.dart';

class TransferFundsBetweenAccountsInput {
  final String fromAccountId;
  final String toAccountId;
  final int amount;

  TransferFundsBetweenAccountsInput({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
  }) : assert(amount > 0);

  Map<String, dynamic> toJson() => {
    'fromAccountId': fromAccountId,
    'toAccountId': toAccountId,
    'amount': amount,
  };

  static TransferFundsBetweenAccountsInput fromJson(
    Map<String, dynamic> json,
  ) => TransferFundsBetweenAccountsInput(
    fromAccountId: json['fromAccountId'] as String,
    toAccountId: json['toAccountId'] as String,
    amount: json['amount'] as int,
  );
}

/// An example of using multiple streams + consistency check
class TransferFundsBetweenAccounts
    implements Command<TransferFundsBetweenAccountsInput> {
  @override
  String get kind => 'transferFundsBetweenAccounts';

  @override
  parseDetail(str) {
    return TransferFundsBetweenAccountsInput.fromJson(jsonDecode(str));
  }

  @override
  String encodeDetail(input) {
    return jsonEncode(input.toJson());
  }

  @override
  Future<void> handle(input, ctx) async {
    final fromStream = ctx.stream(
      accountCodec,
      accountStreamId,
      input.fromAccountId,
    );

    final scanner = fromStream.scan();

    final balance = await scanner.fold(0, (prev, event) {
      switch (event) {
        case AccountAtmDeposited():
          return prev + event.amount;
        case AccountAtmWithdrawn():
          return prev - event.amount;
        case AccountInnerTransfer():
          return prev += event.amount;
        // TODO: new events could be missed here
        default:
          return prev;
      }
    });

    final newBalance = balance - input.amount;

    if (newBalance < 0) {
      return ctx.nack('Insufficient funds');
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

    await toStream.lockLatest();

    toStream.append(
      AccountInnerTransfer(
        fromAccountId: input.fromAccountId,
        amount: input.amount,
      ),
    );
  }
}
