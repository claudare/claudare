import 'dart:convert';

import 'package:core/src/cqrs.dart';

part 'account_atm_deposited.dart';
part 'account_atm_withdrawn.dart';
part 'account_inner_transfer.dart';
part 'account_opened.dart';
part 'account_renamed.dart';

// Using this as a guide for the domain terminology
// https://www.helpwithmybank.gov/glossary/index-glossary.html
// Practice CQRS. Implement:
// - balance correction with reason
// - reversal of transfers
// - editing of the trascations
sealed class AccountEvent {
  const AccountEvent();
}

const accountCodec = AccountCodec();

class AccountCodec implements EventCodec<AccountEvent> {
  const AccountCodec();

  @override
  encode(event) {
    switch (event) {
      case AccountOpened():
        return EncodedEvent(
          kind: AccountOpened.kind,
          detail: jsonEncode(event.toJson()),
        );
      case AccountAtmDeposited():
        return EncodedEvent(
          kind: AccountAtmDeposited.kind,
          detail: jsonEncode(event.toJson()),
        );
      case AccountAtmWithdrawn():
        return EncodedEvent(
          kind: AccountAtmWithdrawn.kind,
          detail: jsonEncode(event.toJson()),
        );
      case AccountInnerTransfer():
        return EncodedEvent(
          kind: AccountInnerTransfer.kind,
          detail: jsonEncode(event.toJson()),
        );
      case AccountRenamed():
        return EncodedEvent(
          kind: AccountRenamed.kind,
          detail: jsonEncode(event.toJson()),
        );
    }
  }

  @override
  decode(encoded) {
    final map = jsonDecode(encoded.detail);
    switch (encoded.kind) {
      case AccountOpened.kind:
        return AccountOpened.fromJson(map);
      case AccountAtmDeposited.kind:
        return AccountAtmDeposited.fromJson(map);
      case AccountAtmWithdrawn.kind:
        return AccountAtmWithdrawn.fromJson(map);
      case AccountInnerTransfer.kind:
        return AccountInnerTransfer.fromJson(map);
      case AccountRenamed.kind:
        return AccountRenamed.fromJson(map);
      default:
        throw Exception("unknown event kind ${encoded.kind}");
    }
  }
}
