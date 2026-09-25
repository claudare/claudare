part of 'account.dart';

class AccountOpened extends AccountEvent {
  static const String kind = 'accountOpened';

  @override
  final String accountId;
  final String name;

  const AccountOpened({required this.accountId, required this.name});

  @override
  toJson() => {'accountId': accountId, 'name': name};

  factory AccountOpened.fromJson(Map<String, dynamic> json) => AccountOpened(
    accountId: json['accountId'] as String,
    name: json['name'] as String,
  );
}

final class AccountOpenedCodec implements EventCodec<AccountOpened> {
  const AccountOpenedCodec();

  @override
  String get kind => AccountOpened.kind;

  @override
  Uint8List toBytes(AccountOpened event) =>
      JsonConverter.encode(event.toJson());

  @override
  AccountOpened fromBytes(Uint8List bytes) =>
      AccountOpened.fromJson(JsonConverter.decode(bytes));
}
