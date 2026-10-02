import 'dart:convert';

import 'package:cqrs/cqrs.dart';
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
    final data = switch (input) {
      ReplicationMessageDependency(:final dependencies) => {
        'type': 'dependency',
        'dependencies': dependencies.toJson(),
      },
      ReplicationMessageCommand(:final command) => {
        'type': 'command',
        'command': command.toJson(),
      },
      ReplicationMessageCommandAck(:final commandId) => {
        'type': 'commandAck',
        'commandId': commandId.toJson(),
      },
    };
    return jsonEncode(
      ProxyMessage(
        type: ProxyMessageType.direct,
        actor: peerActor,
        data: jsonEncode(data),
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
    final data = jsonDecode(proxy.data) as Map<String, dynamic>;
    return switch (data['type']) {
      'dependency' => ReplicationMessageDependency(
        CommandDependency.fromJson(
          data['dependencies'] as Map<String, dynamic>,
        ),
      ),
      'command' => ReplicationMessageCommand(
        StoredCommand.fromJson(data['command'] as Map<String, dynamic>),
      ),
      'commandAck' => ReplicationMessageCommandAck(
        CommandId.fromJson(data['commandId'] as List<dynamic>),
      ),
      _ => throw FormatException(
        'Unknown replication message type: ${data['type']}',
      ),
    };
  }
}
