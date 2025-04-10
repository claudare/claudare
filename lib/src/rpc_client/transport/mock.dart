import 'dart:async';
import 'dart:typed_data';

import 'package:core/src/rpc_client/transport.dart';

class RpcClientTransportMock extends RpcClientTransport {
  StreamController<Uint8List> inputController = StreamController<Uint8List>();
  StreamController<Uint8List> outputController = StreamController<Uint8List>();

  RpcClientConnectionStatus _status = RpcClientConnectionStatus.disconnected;
  final _connectionStatusController =
      StreamController<RpcClientConnectionStatus>.broadcast();

  Future<void> Function(RpcClientTransportMock)? onConnectFn;
  Future<void> Function(RpcClientTransportMock)? onDisconnectFn;

  RpcClientTransportMock({this.onConnectFn, this.onDisconnectFn});

  void setStatus(RpcClientConnectionStatus status) {
    _status = status;
    _connectionStatusController.add(status);
  }

  @override
  StreamSink<Uint8List> get sink => outputController.sink;

  @override
  Stream<Uint8List> get stream => inputController.stream;

  @override
  Stream<RpcClientConnectionStatus> get connectionStatusStream =>
      _connectionStatusController.stream;

  @override
  RpcClientConnectionStatus get connectionStatus => _status;

  @override
  Future<void> connect(Uri endpoint) async {
    if (onConnectFn != null) {
      return await onConnectFn!(this);
    }

    // normal behavior is set to connected
    setStatus(RpcClientConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    if (onDisconnectFn != null) {
      return await onDisconnectFn!(this);
    }
    setStatus(RpcClientConnectionStatus.disconnected);
  }
}
