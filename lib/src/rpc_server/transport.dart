import 'dart:typed_data';

typedef RpcServerHandler = Future<Uint8List> Function(Uint8List);

abstract class RpcServerTransport {
  int get port; // for tests, maybe UI?
  Future<void> start(Uri uri, RpcServerHandler handler);
  Future<void> stop();
}
