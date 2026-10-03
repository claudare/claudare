import 'dart:convert';

import 'package:sync/src/replication/replication_message.dart';

/// Encodes one peer's [ReplicationMessage]s as JSON strings.
class ReplicationMessageCodec extends Codec<ReplicationMessage, String> {
  const ReplicationMessageCodec();

  @override
  Converter<String, ReplicationMessage> get decoder =>
      const _ReplicationMessageDecoder();

  @override
  Converter<ReplicationMessage, String> get encoder =>
      const _ReplicationMessageEncoder();
}

class _ReplicationMessageEncoder extends Converter<ReplicationMessage, String> {
  const _ReplicationMessageEncoder();

  @override
  String convert(ReplicationMessage input) => jsonEncode(input.toJson());

  @override
  Stream<String> bind(Stream<ReplicationMessage> stream) => stream.map(convert);
}

class _ReplicationMessageDecoder extends Converter<String, ReplicationMessage> {
  const _ReplicationMessageDecoder();

  @override
  ReplicationMessage convert(String input) =>
      ReplicationMessage.fromJson(jsonDecode(input));

  @override
  Stream<ReplicationMessage> bind(Stream<String> stream) => stream.map(convert);
}
