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
