import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';

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
