import 'dart:convert';

import 'package:sync/sync.dart';

class ReplicationMessageCodec extends Codec<ReplicationMessage, dynamic> {
  final String peerActor;

  const ReplicationMessageCodec(this.peerActor);

  @override
  Converter<dynamic, ReplicationMessage> get decoder =>
      _ReplicationMessageDecoder(peerActor);

  @override
  Converter<ReplicationMessage, dynamic> get encoder =>
      _ReplicationMessageEncoder(peerActor);
}

class _ReplicationMessageEncoder
    extends Converter<ReplicationMessage, dynamic> {
  final String peerActor;

  const _ReplicationMessageEncoder(this.peerActor);

  @override
  String convert(ReplicationMessage input) {
    return jsonEncode(
      ProxyMessage(
        type: ProxyMessageType.direct,
        actor: peerActor,
        data: jsonEncode(input.toJson()),
      ).toJson(),
    );
  }
}

class _ReplicationMessageDecoder
    extends Converter<dynamic, ReplicationMessage> {
  final String peerActor;

  const _ReplicationMessageDecoder(this.peerActor);

  @override
  ReplicationMessage convert(dynamic input) {
    final proxy = ProxyMessage.fromJson(
      jsonDecode(input as String) as Map<String, dynamic>,
    );
    if (proxy.actor != peerActor) {
      throw FormatException('Unexpected peer: ${proxy.actor}');
    }
    return ReplicationMessage.fromJson(
      jsonDecode(proxy.data) as Map<String, dynamic>,
    );
  }
}
