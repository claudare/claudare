import 'package:core/core.dart';
import 'package:core/rpc_client.dart';
import 'package:core/src/rpc_client/transport/mock.dart';
import 'package:test/test.dart';

import '../rpc_helpers.dart';

// this is a useless test, as the transport is tested using end-to-end strategy
void main() {
  group('RpcClient', () {
    final deviceKeychain = TestKeychainPairs.fromIds(
      DeviceId(1000),
      DeviceId(0),
    );
    test('happy path', () async {
      final transport = RpcClientTransportMock();

      final rpcClient = RpcClient(transport, deviceKeychain.client);

      expectLater(
        rpcClient.connectionStatusStream,
        emitsInOrder([
          RpcClientConnectionStatus.connected,
          RpcClientConnectionStatus.disconnected,
        ]),
      );

      await rpcClient.connect(Uri());
      expect(
        transport.connectionStatus,
        equals(RpcClientConnectionStatus.connected),
      );

      await rpcClient.disconnect();
      expect(
        transport.connectionStatus,
        equals(RpcClientConnectionStatus.disconnected),
      );
    });
  });
}
