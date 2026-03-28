import 'dart:async';
import 'dart:typed_data';

import 'package:core/src/net_connection.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

class ClientConnectionWebsocket extends NetConnection {
  static bool isWebsocketUri(Uri uri) {
    return uri.scheme == 'ws' || uri.scheme == 'wss';
  }

  final _inputController = StreamController<Uint8List>();
  final _outputController = StreamController<Uint8List>();
  StreamSubscription? _wsSubscription;
  StreamSubscription? _outputSubscription;

  WebSocketChannel? _channel;

  ClientConnectionWebsocket() {
    _outputSubscription = _outputController.stream.listen(
      (data) {
        if (_channel == null) {
          throw Exception('Cannot send to disconnected websocket');
        }
        _channel!.sink.add(data);
      },
      onError: (error) {
        _inputController.addError(error);
      },
    );
  }

  @override
  StreamSink<Uint8List> get sink => _outputController.sink;

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  Future<void> connect(Uri endpoint) async {
    if (_channel != null) {
      throw StateError('Already connected or connecting');
    }

    if (endpoint.scheme != 'ws' && endpoint.scheme != 'wss') {
      throw ArgumentError(
        'Cannot connect to $endpoint as scheme is not websockets',
      );
    }

    final channel = WebSocketChannel.connect(endpoint);
    _channel = channel;

    // Setup WebSocket stream subscription
    _wsSubscription = channel.stream.listen(
      (data) {
        if (data is! Uint8List) {
          _inputController.addError(
            FormatException('Received non-binary message: $data'),
          );
          return;
        }
        _inputController.add(data);
      },
      onError: (error) {
        _inputController.addError(error);
        _handleDisconnect();
      },
      onDone: () {
        _handleDisconnect();
      },
    );

    try {
      await channel.ready;
    } catch (e) {
      await _handleDisconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_channel == null) {
      throw StateError('Cannot disconnect as not connected');
    }

    await _channel!.sink.close(status.normalClosure);
    await _handleDisconnect();
  }

  Future<void> _handleDisconnect() async {
    // does cancelling the subscription stop websocket connection?
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    _channel = null;
    await _outputSubscription?.cancel();
    await _inputController.close();
    await _outputController.close();
  }
}
