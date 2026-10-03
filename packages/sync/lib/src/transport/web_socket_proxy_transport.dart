import 'package:web_socket_channel/io.dart';

import 'package:sync/sync.dart';

class WebSocketProxyTransport implements Transport {
  final String _baseUrl;
  final String _thisActor;
  final String _group;

  const WebSocketProxyTransport({
    required this._baseUrl,
    required this._thisActor,
    required this._group,
  });

  @override
  Future<void> close() {
    // TODO: implement close
    throw UnimplementedError();
  }

  @override
  // TODO: implement peerTransports
  Stream<PeerTransport> get peerTransports => throw UnimplementedError();

  @override
  Future<void> start() async {
    // TODO: implement start

    final channel = IOWebSocketChannel.connect(
      _baseUrl,
      headers: ProxyInit(actor: _thisActor, group: _group).toHeaders(),
    );

    await channel.ready;

    throw UnimplementedError();
  }
}
