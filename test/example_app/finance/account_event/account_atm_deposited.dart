part of 'account.dart';

class AccountAtmDeposited extends AccountEvent {
  static const String kind = 'accountAtmDeposited';

  final int amount;

  const AccountAtmDeposited({required this.amount});

  toJson() => {'amount': amount};

  factory AccountAtmDeposited.fromJson(Map<String, dynamic> json) =>
      AccountAtmDeposited(amount: json['amount'] as int);
}
