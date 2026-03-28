part of 'account.dart';

class AccountOpened extends AccountEvent {
  static const String kind = 'accountOpened';

  final String name;

  const AccountOpened({required this.name});

  toJson() => {'name': name};

  factory AccountOpened.fromJson(Map<String, dynamic> json) =>
      AccountOpened(name: json['name'] as String);
}
