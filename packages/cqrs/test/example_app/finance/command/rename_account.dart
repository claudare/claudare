import 'dart:typed_data' show Uint8List;

import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class RenameAccountInput implements CommandInput {
  final String accountId;
  final String newName;

  const RenameAccountInput({required this.accountId, required this.newName});

  @override
  String get kind => 'RenameAccount';

  @override
  Uint8List encode() {
    return JsonConverter.encode({'accountId': accountId, 'newName': newName});
  }
}

class RenameAccount implements Command<RenameAccountInput> {
  @override
  Future<void> handle(input, ctx) async {
    final stream = ctx.stream(
      accountCodec,
      accountStreamRoute,
      input.accountId,
    );

    await stream.mustExist();

    stream.append(AccountRenamed(newName: input.newName));
  }
}
