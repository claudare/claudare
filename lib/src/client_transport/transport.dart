import 'package:core/src/client_transport/connection/websocket.dart';
import 'package:core/src/net_connection.dart';

// this transport needs to create a connection based on the URI
class ClientTransport {
  const ClientTransport();

  /// Returns a new connection connection. Waits for it to connect first.
  /// If connection errors occur, this method throws
  Future<NetConnection> newConnection(Uri uri) async {
    if (ClientConnectionWebsocket.isWebsocketUri(uri)) {
      final conn = ClientConnectionWebsocket();
      await conn.connect(uri);
      return conn;
    } else {
      throw Exception("Unknown transport for uri $uri");
    }
  }
}
