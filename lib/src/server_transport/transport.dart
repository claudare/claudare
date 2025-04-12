import 'package:core/src/net_connection.dart';

abstract class ServerTransport {
  /// starts the server and returns a connection uri
  Future<Uri> start(Uri uri, Function(NetConnection) onConnection);
  Future<void> stop();

  // this should be subsribeable when new client is created
  // should this be a stream, or just a callback?
}
