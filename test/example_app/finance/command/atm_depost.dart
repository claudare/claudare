import 'dart:convert';

import 'package:core/src/cqrs.dart';

import '../account_event/account.dart';
import '../stream_id/account_stream_id.dart';

class AtmDepositInput {
  final String accountId;
  final int amount;

  AtmDepositInput({required this.accountId, required this.amount})
    : assert(amount > 0);

  Map<String, dynamic> toJson() => {'accountId': accountId, 'amount': amount};

  static AtmDepositInput fromJson(Map<String, dynamic> json) => AtmDepositInput(
    accountId: json['accountId'] as String,
    amount: json['amount'] as int,
  );
}

class AtmDeposit implements Command<AtmDepositInput> {
  @override
  String get kind => 'AtmDeposit';

  @override
  parseDetail(str) {
    return AtmDepositInput.fromJson(jsonDecode(str));
  }

  @override
  String encodeDetail(input) {
    return jsonEncode(input.toJson());
  }

  @override
  Future<void> handle(input, ctx) async {
    final stream = ctx.stream(accountCodec, accountStreamId, input.accountId);

    stream.lockLatest();

    stream.append(AccountAtmDeposited(amount: input.amount));
  }
}
