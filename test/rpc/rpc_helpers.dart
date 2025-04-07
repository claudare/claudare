import 'package:core/src/rpc_client/rpc_client.dart';
import 'package:core/src/rpc_client/transport.dart';
import 'package:core/src/rpc_server/handler.dart';
import 'package:core/src/rpc_server/rpc_server.dart';
import 'package:core/src/rpc_server/transport.dart';

class MockRpc {
  final RpcServer server;
  final RpcClient client;

  const MockRpc(this.server, this.client);

  Future<void> close() async {
    await client.disconnect();
    await server.stop();
  }
}

/// This function that will start rpc server and create a client to connect to
/// it on a random port.
Future<MockRpc> mockHttpHandlers(
  RpcServerTransport serverTransport,
  RpcClientTransport clientTransport,
  ServerHandlerFn serverHandler,
) async {
  final rpcServer = RpcServer(serverTransport, serverHandler);

  await rpcServer.start(Uri.parse("http://0.0.0.0:0/test"));
  final port = serverTransport.port;

  final rpcClient = RpcClient(clientTransport);
  await rpcClient.connect(Uri.parse('http://localhost:$port/test'));

  return MockRpc(rpcServer, rpcClient);
}
