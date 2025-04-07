import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/rpc_client/transport.dart';
import 'package:http/http.dart' as http;

class RpcClientTransportHttp extends RpcClientTransport {
  final _inputController = StreamController<Uint8List>();
  final _outputController = StreamController<Uint8List>();
  late Uri endpoint;
  late http.Client _client;

  RpcClientTransportHttp() {
    // Handle outgoing messages
    _outputController.stream.listen(_handleOutgoingMessage);
  }

  Future<void> _handleOutgoingMessage(Uint8List data) async {
    try {
      final response = await _client.post(
        endpoint,
        body: data,
        headers: {'Content-Type': 'application/octet-stream'},
      );

      if (response.statusCode != 200) {
        final debugMsg = utf8.decode(response.bodyBytes);
        _inputController.addError(
          http.ClientException('[${response.statusCode}] $debugMsg', endpoint),
        );
        return;
      }

      if (response.bodyBytes.isNotEmpty) {
        _inputController.add(response.bodyBytes);
      }
    } catch (e) {
      _inputController.addError(e);
    }
  }

  @override
  StreamSink<Uint8List> get sink => _outputController.sink;

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  @override
  Future<void> connect(Uri endpoint) async {
    if (endpoint.scheme != 'http' && endpoint.scheme != 'https') {
      throw Exception('Cant connect to $endpoint as scheme is not http');
    }

    this.endpoint = endpoint;
    _client = http.Client();
    // http does nothing. maybe does a ping to check that server is available
  }

  @override
  Future<void> disconnect() async {
    await _outputController.close();
    await _inputController.close();
    _client.close();
  }

  @override
  RpcClientConnectionStatus status() {
    return RpcClientConnectionStatus.connected;
  }
}
