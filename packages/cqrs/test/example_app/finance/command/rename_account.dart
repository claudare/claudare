import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class RenameAccount implements Command {
  final String accountId;
  final String newName;

  const RenameAccount({required this.accountId, required this.newName});

  @override
  Future<void> handle(ctx) async {
    final stream = ctx.stream<AccountEvent>(
      accountStreamRoute.buildPath(accountId),
    );

    await stream.mustExist();

    stream.append(AccountRenamed(newName: newName));
  }
}
