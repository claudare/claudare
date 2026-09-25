part of 'account.dart';

class AccountAtmDeposited extends AccountEvent {
  static const String kind = 'accountAtmDeposited';

  @override
  final String accountId;
  final int amount;

  const AccountAtmDeposited({required this.accountId, required this.amount});

  @override
  toJson() => {'accountId': accountId, 'amount': amount};

  factory AccountAtmDeposited.fromJson(Map<String, dynamic> json) =>
      AccountAtmDeposited(
        accountId: json['accountId'] as String,
        amount: json['amount'] as int,
      );
}

final class AccountAtmDepositedCodec
    implements EventCodec<AccountAtmDeposited> {
  const AccountAtmDepositedCodec();

  @override
  String get kind => AccountAtmDeposited.kind;

  @override
  Uint8List toBytes(AccountAtmDeposited event) =>
      JsonConverter.encode(event.toJson());

  @override
  AccountAtmDeposited fromBytes(Uint8List bytes) =>
      AccountAtmDeposited.fromJson(JsonConverter.decode(bytes));
}
