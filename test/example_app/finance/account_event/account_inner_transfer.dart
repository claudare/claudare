part of 'account.dart';

class AccountInnerTransfer extends AccountEvent {
  static const String kind = 'accountInnerTransfer';

  final String fromAccountId;
  final int amount;

  const AccountInnerTransfer({
    required this.fromAccountId,
    required this.amount,
  });

  toJson() => {'fromAccountId': fromAccountId, 'amount': amount};

  factory AccountInnerTransfer.fromJson(Map<String, dynamic> json) =>
      AccountInnerTransfer(
        fromAccountId: json['fromAccountId'] as String,
        amount: json['amount'] as int,
      );
}
