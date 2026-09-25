import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class OpenAccount implements Command {
  final String accountId;
  final String name;

  const OpenAccount({required this.accountId, required this.name});

  @override
  Future<void> handle(ctx) async {
    final stream = ctx.stream<AccountEvent>(
      accountStreamRoute.buildPath(accountId),
    );

    // TODO: would be nice to check that no other account has the same name?

    await stream.mustNotExist();

    stream.append(AccountOpened(name: name));
  }
}
