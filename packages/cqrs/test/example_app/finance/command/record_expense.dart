import 'dart:convert';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../paths.dart';

/// Parses an example receipt and records an expense with its original bytes.
class RecordExpense implements Command {
  final String accountId;
  final Uint8List receiptBytes;

  RecordExpense({required this.accountId, required Uint8List receiptBytes})
    : receiptBytes = Uint8List.fromList(receiptBytes).asUnmodifiableView();

  @override
  Future<void> handle(CommandContextApi ctx) async {
    final amount = _parseAmount();
    final stream = ctx.stream<AccountEvent>(accountStream(accountId));
    var exists = false;
    var balance = 0;

    await for (final event in stream.scan()) {
      switch (event) {
        case AccountOpened():
          exists = true;
        case AccountAtmDeposited(:final amount):
          balance += amount;
        case AccountAtmWithdrawn(:final amount):
          balance -= amount;
        case AccountExpenseRecorded(:final amount):
          balance -= amount;
        case AccountInnerTransfer(:final amount):
          balance += amount;
        case AccountRenamed():
          break;
      }
    }

    if (!exists) {
      throw StreamNotFoundException(accountStream(accountId));
    }
    if (balance < amount) {
      throw const CommandException('insufficient funds');
    }

    final receiptBlobId = ctx.generateId();
    ctx.saveBlob(receiptBlobId, receiptBytes);
    stream.append(
      AccountExpenseRecorded(
        accountId: accountId,
        amount: amount,
        receiptBlobId: receiptBlobId,
      ),
    );
  }

  int _parseAmount() {
    final dynamic receipt;
    try {
      receipt = jsonDecode(utf8.decode(receiptBytes));
    } on FormatException {
      throw const CommandException('receipt must be a JSON object');
    }
    if (receipt is! Map<String, dynamic>) {
      throw const CommandException('receipt must be a JSON object');
    }
    final amount = receipt['amount'];
    if (amount is! int || amount <= 0) {
      throw const CommandException('receipt amount must be a positive integer');
    }
    return amount;
  }
}
