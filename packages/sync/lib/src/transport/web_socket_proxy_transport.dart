import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:sync/sync.dart';

class WebSocketProxyTransport {
  final String _baseUrl;
  final String _thisActor;

  const WebSocketProxyTransport({
    required this._baseUrl,
    required this._thisActor,
  });

  Uri get _connectUri => Uri.parse('$_baseUrl/$_thisActor');

  Future<ReplicationChannel> connect(String peerActor) async {
    final channel = WebSocketChannel.connect(_connectUri);

    await channel.ready;

    return channel.transform(
      StreamChannelTransformer.fromCodec(_ReplicationMessageCodec(peerActor)),
    );
  }
}

class _ReplicationMessageCodec extends Codec<ReplicationMessage, dynamic> {
  final String peerActor;

  const _ReplicationMessageCodec(this.peerActor);

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
