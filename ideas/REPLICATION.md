# Replication overview

This is an ideation document. It describes future boundaries and illustrative
API shapes only. None of these packages, protocols, or transports is
implemented.

## Package boundaries

| Package | Owns | Does not own |
| --- | --- | --- |
| `device_identity` | Device public keys and persistent local ID mappings | CQRS event storage, transport connections, peer registration, or replication |
| `networking` | Transport connections, connection addresses, factory selection, hosting, broadcasting, and inbound connection streams | Device identity, enrollment, retry policy, or replication protocol |
| `peers` | Peer registration, peer connection, public-key preambles, and host/broadcast coordination | Identity persistence, transport implementation, or replication |
| system storage | One separate SQLite handle shared by system subsystems, plus one adapter and migration table per subsystem | CQRS/runtime storage or application event history |
| `cqrs` | Local event storage and database-local integer device IDs used by commands and version vectors | Stable device identity, enrollment, discovery, or transport |
| future replication layer | Identity-map exchange, local-ID translation, and transfer protocol coordination | Transport implementation, identity persistence, or retry policy |

The replication layer sits above `networking` and `device_identity`. It must
translate all received device IDs and version-vector keys through stable public
keys before giving records to local CQRS storage.

## Identity

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

## Peers

`peers` composes `device_identity` and `networking` without merging their
ownership. It maintains one shared hosting and broadcast lifecycle while
registration is active. Unknown inbound peers are registered and disconnected;
known inbound peers are passed to the connection system as active channels.

```dart
/// Transfers an inviter identity and available connection addresses by QR.
final class PairingInvitation {
  const PairingInvitation({
    required this.inviterPublicKey,
    required this.connectionAddresses,
  });

  final DevicePublicKey inviterPublicKey;
  final List<ConnectionAddress> connectionAddresses;
}

/// The first message on every raw peer channel.
///
/// This MVP only exchanges a public-key claim. It does not authenticate that
/// claim or encrypt the channel.
final class PeerPreamble {
  const PeerPreamble(this.publicKey);

  final DevicePublicKey publicKey;
}

/// An open channel to a registered peer after the preamble completes.
final class PeerConnection {
  const PeerConnection({
    required this.publicKey,
    required this.channel,
    required this.disconnected,
  });

  final DevicePublicKey publicKey;
  final StreamChannel<Uint8List> channel;

  /// Completes when [channel] disconnects or fails.
  final Future<void> disconnected;
}

/// Registers unknown peers through temporary channels.
abstract interface class PeerRegistrar {
  /// Starts hosting and broadcasting through every selected connection type.
  ///
  /// Returns a QR invitation containing the local key and hosted addresses.
  Future<PairingInvitation> startRegistration(
    Iterable<String> connectionTypes,
  );

  /// Accepts a scanned QR invitation and closes the temporary channel after
  /// registration completes.
  ///
  /// The peer's preamble key must match [invitation.inviterPublicKey]. The
  /// remote side receives this device's key and registers it in turn.
  Future<void> acceptInvitation(PairingInvitation invitation);

  /// Stops shared hosting, broadcasting, and new registration intake.
  Future<void> close();
}

/// Connects to peers that are already registered locally.
abstract interface class PeerConnector {
  /// Actively connects to discovered addresses until a preamble claims
  /// [publicKey], then emits the connection through [connections].
  ///
  /// Every invocation starts a new attempt from discovery. Call it again after
  /// [PeerConnection.disconnected] completes to reconnect.
  ///
  /// Completes with an error if [publicKey] is not registered or no matching
  /// connection can be established. Unmatched channels are closed.
  Future<void> connect(DevicePublicKey publicKey);

  /// Every established peer channel, whether dialed or accepted.
  Stream<PeerConnection> get connections;
}
```

`PeerConnector` receives discovered addresses from the active factories, such
as mDNS or Bluetooth broadcasts. Subscribe to [PeerConnector.connections]
before calling `connect`. It must only expose a channel after the peer has
claimed a public key that is already registered locally.

## Limits

No encryption or authentication whatsoever. This is to get an MVP rolling.

Binary encoding, QR rendering, concrete transports, and the replication protocol
remain unimplemented.
