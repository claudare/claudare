import 'package:core/device_keychain.dart';
import 'package:core/src/device_id.dart';

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
