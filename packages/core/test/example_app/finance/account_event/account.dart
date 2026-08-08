import 'package:core/cqrs.dart';
import 'package:core/utils.dart';

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

  Map<String, dynamic> toJson();
}

const accountCodec = AccountCodec();

class AccountCodec implements EventCodec<AccountEvent> {
  const AccountCodec();

  @override
  encode(event) {
    final detail = JsonConverter.encode(event.toJson());
    switch (event) {
      case AccountOpened():
        return EncodedEvent(kind: AccountOpened.kind, bytes: detail);
      case AccountAtmDeposited():
        return EncodedEvent(kind: AccountAtmDeposited.kind, bytes: detail);
      case AccountAtmWithdrawn():
        return EncodedEvent(kind: AccountAtmWithdrawn.kind, bytes: detail);
      case AccountInnerTransfer():
        return EncodedEvent(kind: AccountInnerTransfer.kind, bytes: detail);
      case AccountRenamed():
        return EncodedEvent(kind: AccountRenamed.kind, bytes: detail);
    }
  }

  @override
  decode(encoded) {
    final map = JsonConverter.decode(encoded.bytes);
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
        throw Exception('unknown event kind ${encoded.kind}');
    }
  }
}
