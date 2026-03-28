part of 'account.dart';

class AccountRenamed extends AccountEvent {
  static const String kind = 'accountRenamed';

  final String newName;

  const AccountRenamed({required this.newName});

  toJson() => {'newName': newName};

  factory AccountRenamed.fromJson(Map<String, dynamic> json) =>
      AccountRenamed(newName: json['newName'] as String);
}
