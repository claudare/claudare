part of 'account.dart';

class AccountInnerTransfer extends AccountEvent {
  static const String kind = 'accountInnerTransfer';

  @override
  final String accountId;
  final String fromAccountId;
  final int amount;

  const AccountInnerTransfer({
    required this.accountId,
    required this.fromAccountId,
    required this.amount,
  });

  @override
  toJson() => {
    'accountId': accountId,
    'fromAccountId': fromAccountId,
    'amount': amount,
  };

  factory AccountInnerTransfer.fromJson(Map<String, dynamic> json) =>
      AccountInnerTransfer(
        accountId: json['accountId'] as String,
        fromAccountId: json['fromAccountId'] as String,
        amount: json['amount'] as int,
      );
}

final class AccountInnerTransferCodec
    implements EventCodec<AccountInnerTransfer> {
  const AccountInnerTransferCodec();

  @override
  String get kind => AccountInnerTransfer.kind;

  @override
  Uint8List toBytes(AccountInnerTransfer event) =>
      JsonConverter.encode(event.toJson());

  @override
  AccountInnerTransfer fromBytes(Uint8List bytes) =>
      AccountInnerTransfer.fromJson(JsonConverter.decode(bytes));
}
