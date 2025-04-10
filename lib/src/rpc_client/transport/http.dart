import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/rpc_client/transport.dart';
import 'package:http/http.dart' as http;

class RpcClientTransportHttp extends RpcClientTransport {
  late StreamController<Uint8List> _inputController;
  late StreamController<Uint8List> _outputController;
  late Uri _endpoint;
  late http.Client _client;

  RpcClientConnectionStatus _status = RpcClientConnectionStatus.disconnected;
  final _connectionStatusController =
      StreamController<RpcClientConnectionStatus>.broadcast();

  RpcClientTransportHttp();

  Future<void> _handleOutgoingMessage(Uint8List requestData) async {
    try {
      final response = await _client.post(
        _endpoint,
        body: requestData,
        headers: {'Content-Type': 'application/octet-stream'},
      );

      // this also means there is an internal error
      // everything must be 200, even the nacks!
      if (response.statusCode != 200) {
        final debugMsg = utf8.decode(response.bodyBytes);
        _inputController.addError(
          http.ClientException('[${response.statusCode}] $debugMsg', _endpoint),
        );
        return;
      }

      if (response.bodyBytes.isNotEmpty) {
        _inputController.add(response.bodyBytes);
      }
    } catch (e) {
      // try to clear the nack?

      _inputController.addError(e);
    }
  }

  @override
  StreamSink<Uint8List> get sink => _outputController.sink;

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  @override
  Stream<RpcClientConnectionStatus> get connectionStatusStream =>
      _connectionStatusController.stream;

  @override
  RpcClientConnectionStatus get connectionStatus => _status;

  @override
  Future<void> connect(Uri endpoint) async {
    if (endpoint.scheme != 'http' && endpoint.scheme != 'https') {
      throw Exception('Cant connect to $endpoint as scheme is not http');
    }

    _inputController = StreamController<Uint8List>();
    _outputController = StreamController<Uint8List>();
    _endpoint = endpoint;
    _client = http.Client();

    _outputController.stream.listen(_handleOutgoingMessage);

    // http does nothing. maybe does a ping to check that server is available
    _setStatus(RpcClientConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    await _outputController.close();
    await _inputController.close();
    _client.close();

    _setStatus(RpcClientConnectionStatus.disconnected);
  }

  void _setStatus(RpcClientConnectionStatus status) {
    _status = status;
    _connectionStatusController.add(status);
  }
}
