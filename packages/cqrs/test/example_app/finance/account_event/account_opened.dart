part of 'account.dart';

class AccountOpened extends AccountEvent {
  static const String kind = 'accountOpened';

  final String name;

  const AccountOpened({required this.name});

  @override
  toJson() => {'name': name};

  factory AccountOpened.fromJson(Map<String, dynamic> json) =>
      AccountOpened(name: json['name'] as String);
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
