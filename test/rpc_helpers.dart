import 'package:core/device_keychain.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/rpc_client/rpc_client.dart';
import 'package:core/src/rpc_client/transport.dart';
import 'package:core/src/rpc_server/rpc_server.dart';
import 'package:core/src/rpc_server/transport.dart';

class TestKeychainPairs {
  final DeviceKeychain server;
  final DeviceKeychain client;

  const TestKeychainPairs(this.server, this.client);

  factory TestKeychainPairs.fromIds(DeviceId serverId, DeviceId clientId) {
    final serverKeychain = DeviceKeychain.empty(serverId);
    serverKeychain.enroll(DeviceEnrollment(clientId, false));

    final clientKeychain = DeviceKeychain.empty(clientId);
    clientKeychain.enroll(DeviceEnrollment(serverId, true));

    return TestKeychainPairs(serverKeychain, clientKeychain);
  }
}

class TestRpc {
  final RpcServer server;
  final RpcClient client;
  final TestKeychainPairs keychains;

  const TestRpc(this.server, this.client, this.keychains);

  Future<void> close() async {
    await client.disconnect();
    await server.stop();
  }
}

/// This function that will start rpc server and create a client to connect to
/// it on a random port.
/// Client is given deviceId of 0. server has deviceId of 1000
Future<TestRpc> mockHttpHandlers(
  RpcServerTransport serverTransport,
  RpcClientTransport clientTransport,
  ServerHandlerFn serverHandler,
) async {
  final keychains = TestKeychainPairs.fromIds(DeviceId(1000), DeviceId(0));

  final rpcServer = RpcServer(serverTransport, keychains.server, serverHandler);

  await rpcServer.start(Uri.parse("http://0.0.0.0:0/test"));
  final port = serverTransport.port;

  final rpcClient = RpcClient(clientTransport, keychains.client);
  await rpcClient.connect(Uri.parse('http://localhost:$port/test'));

  return TestRpc(rpcServer, rpcClient, keychains);
}
