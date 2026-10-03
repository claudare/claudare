import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:sync/src/replication/replication_message_codec.dart';
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
      StreamChannelTransformer.fromCodec(ReplicationMessageCodec(peerActor)),
    );
  }
}
