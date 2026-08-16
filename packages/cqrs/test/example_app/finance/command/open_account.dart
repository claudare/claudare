import 'dart:typed_data' show Uint8List;

import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';

import '../account_event/account.dart';
import '../stream_route/account_stream_route.dart';

class OpenAccountInput implements CommandInput {
  final String name;

  const OpenAccountInput({required this.name});

  @override
  String get kind => 'OpenAccount';

  @override
  Uint8List encode() => JsonConverter.encode({'name': name});
}

class OpenAccount implements Command<OpenAccountInput> {
  @override
  Future<void> handle(input, ctx) async {
    final accountId = ctx.newId();

    final stream = ctx.stream(accountCodec, accountStreamRoute, accountId);

    // TODO: would be nice to check that no other account has the same name?

    await stream.mustNotExist();

    stream.append(AccountOpened(name: input.name));
  }
}
