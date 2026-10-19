import 'dart:convert';

import 'package:sync/src/replication/command_replication_message.dart';

/// Encodes one peer's [CommandReplicationMessage]s as JSON strings.
class CommandReplicationMessageCodec
    extends Codec<CommandReplicationMessage, String> {
  const CommandReplicationMessageCodec();

  @override
  Converter<String, CommandReplicationMessage> get decoder =>
      const _CommandReplicationMessageDecoder();

  @override
  Converter<CommandReplicationMessage, String> get encoder =>
      const _CommandReplicationMessageEncoder();
}

class _CommandReplicationMessageEncoder
    extends Converter<CommandReplicationMessage, String> {
  const _CommandReplicationMessageEncoder();

  @override
  String convert(CommandReplicationMessage input) => jsonEncode(input.toJson());

  @override
  Stream<String> bind(Stream<CommandReplicationMessage> stream) =>
      stream.map(convert);
}

class _CommandReplicationMessageDecoder
    extends Converter<String, CommandReplicationMessage> {
  const _CommandReplicationMessageDecoder();

  @override
  CommandReplicationMessage convert(String input) =>
      CommandReplicationMessage.fromJson(jsonDecode(input));

  @override
  Stream<CommandReplicationMessage> bind(Stream<String> stream) =>
      stream.map(convert);
}
