import 'dart:convert';

import 'blob_replication_message.dart';

/// Encodes [BlobReplicationMessage]s as JSON strings with base64 blob bytes.
class BlobReplicationMessageCodec
    extends Codec<BlobReplicationMessage, String> {
  const BlobReplicationMessageCodec();

  @override
  Converter<String, BlobReplicationMessage> get decoder =>
      const _BlobReplicationMessageDecoder();

  @override
  Converter<BlobReplicationMessage, String> get encoder =>
      const _BlobReplicationMessageEncoder();
}

class _BlobReplicationMessageEncoder
    extends Converter<BlobReplicationMessage, String> {
  const _BlobReplicationMessageEncoder();

  @override
  String convert(BlobReplicationMessage input) => jsonEncode(input.toJson());

  @override
  Stream<String> bind(Stream<BlobReplicationMessage> stream) =>
      stream.map(convert);
}

class _BlobReplicationMessageDecoder
    extends Converter<String, BlobReplicationMessage> {
  const _BlobReplicationMessageDecoder();

  @override
  BlobReplicationMessage convert(String input) =>
      BlobReplicationMessage.fromJson(jsonDecode(input));

  @override
  Stream<BlobReplicationMessage> bind(Stream<String> stream) =>
      stream.map(convert);
}
