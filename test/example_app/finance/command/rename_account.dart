import 'dart:convert';

import 'package:core/src/cqrs.dart';

import '../account_event/account.dart';
import '../stream_id/account_stream_id.dart';

class RenameAccountInput {
  final String accountId;
  final String newName;

  RenameAccountInput({required this.accountId, required this.newName});

  Map<String, dynamic> toJson() {
    return {'accountId': accountId, 'newName': newName};
  }

  factory RenameAccountInput.fromJson(Map<String, dynamic> json) {
    return RenameAccountInput(
      accountId: json['accountId'] as String,
      newName: json['newName'] as String,
    );
  }
}

class RenameAccount extends Command<RenameAccountInput> {
  @override
  String get kind => 'renameAccount';

  @override
  String encodeDetail(RenameAccountInput input) {
    return input.toJson().toString();
  }

  @override
  RenameAccountInput parseDetail(String str) {
    return RenameAccountInput.fromJson(jsonDecode(str));
  }

  @override
  Future<void> handle(input, ctx) async {
    final stream = ctx.stream(accountCodec, accountStreamId, input.accountId);

    await stream.lockLatest();

    stream.append(AccountOpened(name: input.newName));
  }
}
