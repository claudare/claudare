part of 'account.dart';

class AccountAtmWithdrawn extends AccountEvent {
  static const String kind = 'accountAtmWithdrawn';

  final int amount;

  const AccountAtmWithdrawn({required this.amount});

  @override
  toJson() => {'amount': amount};

  factory AccountAtmWithdrawn.fromJson(Map<String, dynamic> json) =>
      AccountAtmWithdrawn(amount: json['amount'] as int);
}

final class AccountAtmWithdrawnCodec
    implements EventCodec<AccountAtmWithdrawn> {
  const AccountAtmWithdrawnCodec();

  @override
  String get kind => AccountAtmWithdrawn.kind;

  @override
  Uint8List toBytes(AccountAtmWithdrawn event) =>
      JsonConverter.encode(event.toJson());

  @override
  AccountAtmWithdrawn fromBytes(Uint8List bytes) =>
      AccountAtmWithdrawn.fromJson(JsonConverter.decode(bytes));
}
