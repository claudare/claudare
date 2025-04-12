import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/net_connection.dart';
import 'package:core/src/server_transport/transport.dart';
import 'package:web_socket_channel/status.dart' as status;

class ServerTransportWebsocket extends ServerTransport {
  HttpServer? _server;

  @override
  Future<Uri> start(Uri listenUri, handler) async {
    if (_server != null) {
      throw Exception('Server is already started');
    }

    // extracting the server params from the uri
    // http://0.0.0.0:54321/path
    final host = listenUri.host;
    final port = listenUri.port;
    final path = listenUri.path;

    final server = await HttpServer.bind(host, port);
    _server = server;

    server.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      try {
        final websocket = await WebSocketTransformer.upgrade(request);
        final connection = ServerConnectionWebsocket(websocket);
        handler(connection);
      } catch (e) {
        print('Error handling WebSocket upgrade: $e');
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      }
    });

    return Uri(scheme: "ws", host: host, path: path, port: server.port);
  }

  @override
  Future<void> stop() async {
    await _server?.close(force: false);
  }
}

class ServerConnectionWebsocket extends NetConnection {
  final WebSocket _webSocket;
  final _inputController = StreamController<Uint8List>();
  final _outputController = StreamController<Uint8List>();
  StreamSubscription? _wsSubscription;
  StreamSubscription? _outputSubscription;

  ServerConnectionWebsocket(this._webSocket) {
    _setupWebSocket();
    _setupOutput();
  }

  void _setupWebSocket() {
    _wsSubscription = _webSocket.listen(
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
  }

  void _setupOutput() {
    _outputSubscription = _outputController.stream.listen(
      (data) {
        if (_webSocket.readyState != WebSocket.open) {
          throw Exception('Cannot send to disconnected websocket');
        }
        _webSocket.add(data);
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

  @override
  Future<void> disconnect() async {
    if (_webSocket.readyState != WebSocket.open) {
      throw StateError('Cannot disconnect as not connected');
    }

    await _webSocket.close(status.normalClosure);
    await _handleDisconnect();
  }

  Future<void> _handleDisconnect() async {
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _outputSubscription?.cancel();
    _outputSubscription = null;
    await _inputController.close();
    await _outputController.close();
  }
}
