import 'package:core/core.dart';
import 'package:messagepack/messagepack.dart';

/// [DeviceClaim] is the data attached to communications which is used to
/// prove devices identity for authentication. Authorization is not done here.
/// This will require knowledge of public keys of all participants of this system.
/// For now its just the [DeviceId], trust me system.
class DeviceClaim {
  final DeviceId fromDeviceId;
  final DeviceId forDeviceId;

  const DeviceClaim(this.fromDeviceId, this.forDeviceId);

  void pack(Packer p) {
    fromDeviceId.pack(p);
    forDeviceId.pack(p);
  }

  DeviceClaim.unpack(Unpacker u)
    : fromDeviceId = DeviceId.unpack(u),
      forDeviceId = DeviceId.unpack(u);

  @override
  String toString() {
    return 'DeviceClaim{fromDeviceId: $fromDeviceId, forDeviceId: $forDeviceId}';
  }
}

class DeviceEnrollment {
  final DeviceId deviceId;
  final bool isServer;
  // final Key publicKey
  const DeviceEnrollment(this.deviceId, this.isServer);
}

/// [OwnDevice] has a mechanism to store own private keys securely
/// with https://pub.dev/packages/flutter_secure_storage interface
class OwnDevice {
  final DeviceEnrollment ownEnrollment;

  OwnDevice(DeviceId deviceId)
    : ownEnrollment = DeviceEnrollment(deviceId, false);

  Future<DeviceClaim> makeClaim(DeviceEnrollment forDevice) async {
    return DeviceClaim(ownEnrollment.deviceId, forDevice.deviceId);
  }
}

/// [DeviceKeychain] stores public keys for each of the devices
/// This will perform signing of own proofs and will validate proofs of others.
/// For now it just blindly trusts the device id
/// this will process device enrollement events and keep a projection of
/// all available devices
/// [DeviceKeychain] is how thisDeviceId is stored thought the application
/// TODO: this should use the data structure CValue for enrollments
class DeviceKeychain {
  final OwnDevice _ownDevice;
  final Map<DeviceId, DeviceEnrollment> _devices;

  const DeviceKeychain(this._ownDevice, this._devices);

  factory DeviceKeychain.empty(DeviceId thisDeviceId) {
    return DeviceKeychain(OwnDevice(thisDeviceId), {});
  }

  DeviceId get thisDeviceId => _ownDevice.ownEnrollment.deviceId;

  DeviceId firstServerId() {
    return _devices.entries
        .firstWhere((entry) => entry.value.isServer == true)
        .key;
  }

  void enroll(DeviceEnrollment enrollment) {
    _devices[enrollment.deviceId] = enrollment;
  }

  void unenroll(DeviceId deviceId) {
    final removed = _devices.remove(deviceId);

    if (removed == null) {
      throw Exception(
        'Did not unenroll device $deviceId as it was not enrolled',
      );
    }
  }

  /// Returns the device information if proof is successful.
  /// Throws otherwise.
  Future<DeviceEnrollment> checkClaim(DeviceClaim claim) async {
    final value = _devices[claim.fromDeviceId];

    if (value == null) {
      throw Exception(
        'DeviceClaim validation failed: device ${claim.fromDeviceId} is not enrolled',
      );
    }

    if (claim.forDeviceId != thisDeviceId) {
      throw Exception(
        'DeviceClaim validation failed: expected forDeviceId to be $thisDeviceId, got ${claim.forDeviceId} instead',
      );
    }

    return value;
  }

  Future<DeviceClaim> makeClaim(DeviceId forDeviceId) async {
    final device = _devices[forDeviceId];

    if (device == null) {
      throw Exception(
        'failed to make a claim: DeviceId $forDeviceId is not enrolled',
      );
    }

    return await _ownDevice.makeClaim(device);
  }
}
