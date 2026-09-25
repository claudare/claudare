import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class RenameAccountInput {
  final String accountId;
  final String newName;

  const RenameAccountInput({required this.accountId, required this.newName});
}

class RenameAccount implements Command<RenameAccountInput> {
  @override
  Future<void> handle(input, ctx) async {
    final stream = ctx.stream<AccountEvent>(
      accountStreamRoute.buildPath(input.accountId),
    );

    await stream.mustExist();

    stream.append(AccountRenamed(newName: input.newName));
  }
}
