import 'package:core/cqrs.dart';

import '../account_event/account.dart';
import '../stream_id/account_stream_id.dart';

class RenameAccountInput implements CommandInput {
  final String accountId;
  final String newName;

  RenameAccountInput({required this.accountId, required this.newName});

  @override
  String get kind => 'RenameAccount';

  @override
  Map<String, dynamic> toJson() {
    return {'accountId': accountId, 'newName': newName};
  }
}

class RenameAccount implements Command<RenameAccountInput> {
  @override
  Future<void> handle(input, ctx) async {
    final stream = ctx.stream(accountCodec, accountStreamId, input.accountId);

    await stream.mustExist();

    stream.append(AccountRenamed(newName: input.newName));
  }
}
