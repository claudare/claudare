part of 'account.dart';

/// An expense backed by the original receipt blob.
class AccountExpenseRecorded extends AccountEvent {
  static const String kind = 'accountExpenseRecorded';

  @override
  final String accountId;
  final int amount;
  final String receiptBlobId;

  const AccountExpenseRecorded({
    required this.accountId,
    required this.amount,
    required this.receiptBlobId,
  });

  @override
  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    'amount': amount,
    'receiptBlobId': receiptBlobId,
  };

  factory AccountExpenseRecorded.fromJson(Map<String, dynamic> json) =>
      AccountExpenseRecorded(
        accountId: json['accountId'] as String,
        amount: json['amount'] as int,
        receiptBlobId: json['receiptBlobId'] as String,
      );
}

/// Encodes expense transactions with receipt references.
final class AccountExpenseRecordedCodec
    implements EventCodec<AccountExpenseRecorded> {
  const AccountExpenseRecordedCodec();

  @override
  String get kind => AccountExpenseRecorded.kind;

  @override
  Uint8List toBytes(AccountExpenseRecorded event) =>
      JsonConverter.encode(event.toJson());

  @override
  AccountExpenseRecorded fromBytes(Uint8List bytes) =>
      AccountExpenseRecorded.fromJson(JsonConverter.decode(bytes));
}
