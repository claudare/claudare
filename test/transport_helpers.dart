import 'package:core/src/client_transport/transport.dart';
import 'package:core/src/net_connection.dart';
import 'package:core/src/server_transport/transport.dart';
import 'package:core/src/server_transport/websocket.dart';

class TestServerClientTransport {
  final ServerTransport serverTransport;
  final NetConnection serverConnection;
  final ClientTransport clientTransport;
  final NetConnection clientConnection;

  const TestServerClientTransport(
    this.serverTransport,
    this.serverConnection,
    this.clientTransport,
    this.clientConnection,
  );

  static Future<TestServerClientTransport> websockets() async {
    final serverTransport = ServerTransportWebsocket();
    NetConnection? serverConnection;

    final connectUri = await serverTransport.start(
      Uri.parse("ws://127.0.0.1:0"),
      (conn) {
        serverConnection = conn;
      },
    );

    final clientTransport = ClientTransport();
    final clientConnection = await clientTransport.newConnection(
      // Uri(scheme: "ws", host: "localhost"),
      connectUri,
    );

    return TestServerClientTransport(
      serverTransport,
      serverConnection!,
      clientTransport,
      clientConnection,
    );
  }

  Future<void> stop() async {
    await serverTransport.stop();
    await clientConnection.disconnect();
  }
}
