part of 'account.dart';

class AccountRenamed extends AccountEvent {
  static const String kind = 'accountRenamed';

  @override
  final String accountId;
  final String newName;

  const AccountRenamed({required this.accountId, required this.newName});

  @override
  toJson() => {'accountId': accountId, 'newName': newName};

  factory AccountRenamed.fromJson(Map<String, dynamic> json) => AccountRenamed(
    accountId: json['accountId'] as String,
    newName: json['newName'] as String,
  );
}

final class AccountRenamedCodec implements EventCodec<AccountRenamed> {
  const AccountRenamedCodec();

  @override
  String get kind => AccountRenamed.kind;

  @override
  Uint8List toBytes(AccountRenamed event) =>
      JsonConverter.encode(event.toJson());

  @override
  AccountRenamed fromBytes(Uint8List bytes) =>
      AccountRenamed.fromJson(JsonConverter.decode(bytes));
}
