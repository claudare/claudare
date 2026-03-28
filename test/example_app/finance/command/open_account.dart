import 'dart:convert';

import 'package:core/src/cqrs.dart';

import '../account_event/account.dart';
import '../stream_id/account_stream_id.dart';

class OpenAccountInput {
  final String name;

  const OpenAccountInput({required this.name});

  toJson() => {'name': name};

  factory OpenAccountInput.fromJson(Map<String, dynamic> json) =>
      OpenAccountInput(name: json['name'] as String);
}

class OpenAccount implements Command<OpenAccountInput> {
  @override
  String get kind => 'openAccount';

  @override
  parseDetail(str) {
    return OpenAccountInput.fromJson(jsonDecode(str));
  }

  @override
  String encodeDetail(input) {
    return jsonEncode(input.toJson());
  }

  @override
  Future<void> handle(input, ctx) async {
    final accountId = ctx.newId();

    final stream = ctx.stream(accountCodec, accountStreamId, accountId);

    await stream.mustNotExist();

    stream.append(AccountOpened(name: input.name));
  }
}
