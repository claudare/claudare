import 'package:core/src/cqrs.dart';

import '../account_event/account.dart';
import '../stream_id/account_stream_id.dart';

class OpenAccountInput implements CommandInput {
  final String name;

  const OpenAccountInput({required this.name});

  @override
  String get kind => 'OpenAccount';

  @override
  Map<String, dynamic> toJson() => {'name': name};
}

class OpenAccount implements Command<OpenAccountInput> {
  @override
  Future<void> handle(input, ctx) async {
    final accountId = ctx.newId();

    final stream = ctx.stream(accountCodec, accountStreamId, accountId);

    await stream.mustNotExist();

    stream.append(AccountOpened(name: input.name));
  }
}
