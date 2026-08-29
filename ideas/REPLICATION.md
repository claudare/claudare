# Replication overview

This is an ideation document. It describes future boundaries and illustrative
API shapes only. None of these packages, protocols, or transports is
implemented.

## Package boundaries

| Package                  | Owns                                                                                                                                  | Does not own                                                                 |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `device_identity`        | Device public keys, persistent local ID mappings, QR invitation data, and enrollment registration                                     | CQRS event storage, transport connections, membership policy, or replication |
| `networking`             | Transport connections, connection addresses, connection-type factory selection, hosting, broadcasting, and inbound connection streams | Device identity, enrollment, retry policy, or replication protocol           |
| system storage           | One separate SQLite handle shared by system subsystems, plus one adapter and migration table per subsystem                            | CQRS/runtime storage or application event history                            |
| `cqrs`                   | Local event storage and database-local integer device IDs used by commands and version vectors                                        | Stable device identity, enrollment, discovery, or transport                  |
| future replication layer | Identity-map exchange, local-ID translation, and transfer protocol coordination                                                       | Transport implementation, identity persistence, or retry policy              |

The replication layer sits above `networking` and `device_identity`. It must
translate all received device IDs and version-vector keys through stable public
keys before giving records to local CQRS storage.

## Identity and enrollment

```dart
/// A 32-byte public key encoded as a base64url string.
final class DevicePublicKey {
  const DevicePublicKey(String base64Url);

  String get base64Url;
}

/// Persistently maps device public keys to local CQRS integer IDs.
///
/// ID `0` identifies the local device. Allocated IDs are never reused.
abstract interface class DeviceIdentityStore {
  /// The public key for the local device, whose local ID is `0`.
  DevicePublicKey get localPublicKey;

  /// Persists [publicKey] and returns its local ID.
  Future<int> register(DevicePublicKey publicKey);

  /// Returns the local ID previously registered for [publicKey].
  int idFor(DevicePublicKey publicKey);

  /// Returns the public key previously registered for [deviceId].
  DevicePublicKey publicKeyFor(int deviceId);
}
```

```dart
/// Exchanges a peer's local ID-to-key mappings before replication.
///
/// Entries may include identities relayed by another device. Recipients use the
/// keys to translate device IDs and version-vector keys into local IDs.
final class DeviceIdentityMap {
  const DeviceIdentityMap(Map<int, DevicePublicKey> entries);

  Map<int, DevicePublicKey> get entries;
}
```

```dart
/// Transfers an inviter identity and available connection addresses by QR.
///
/// Scanning registers [inviterPublicKey] locally. Reciprocal registration
/// occurs over the later direct connection.
final class PairingInvitation {
  const PairingInvitation({
    required this.inviterPublicKey,
    required this.connectionAddresses,
  });

  final DevicePublicKey inviterPublicKey;
  final List<ConnectionAddress> connectionAddresses;
}
```

## System storage

System storage is physically separate from CQRS and runtime storage. Its
subsystems share one system SQLite handle, with one adapter and migration table
per subsystem.

## Networking

`networking` owns transport connections and discovery. It does not own identity,
enrollment, or replication.

```dart
/// Describes a transport address for a connection attempt.
///
/// [connectionType] selects the registered factory, for example `memory`.
/// [attributes] hold transport-specific values such as an ID, host, or port.
/// Addresses are supplied by a pairing invitation or discovered broadcast.
final class ConnectionAddress {
  const ConnectionAddress({
    required this.connectionType,
    required this.attributes,
  });

  final String connectionType;
  final Map<String, String> attributes;
}

/// Creates, hosts, and discovers connections for one [connectionType].
abstract interface class ConnectionFactory {
  /// The type used by [ConnectionFactoryRegistry] to select this factory.
  String get connectionType;

  /// Opens a channel to [address], completing with an error on failure.
  Future<StreamChannel<Uint8List>> connect(ConnectionAddress address);

  /// Starts hosting and returns the address needed to connect to this host.
  Future<ConnectionAddress> startHosting();

  /// Stops hosting without changing broadcasting.
  Future<void> stopHosting();

  /// Starts broadcasting [address] without starting a host.
  Future<void> startBroadcasting(ConnectionAddress address);

  /// Stops broadcasting without stopping a host.
  Future<void> stopBroadcasting();

  /// Established connections accepted by the host.
  Stream<StreamChannel<Uint8List>> get incomingConnections;

  /// Connection addresses received through discovery broadcasts.
  Stream<ConnectionAddress> get discoveredConnectionAddresses;
}

/// Selects a connection factory by its connection type.
abstract interface class ConnectionFactoryRegistry {
  ConnectionFactory forConnectionType(String connectionType);
}
```

Retry policy and the decision to host or broadcast belong above networking.

## Limits

No encryption or authentication whatsoever. This is to get an MVP rolling.

Binary encoding, QR rendering, concrete transports, and the replication protocol
remain unimplemented.
