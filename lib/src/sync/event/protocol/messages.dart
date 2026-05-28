import 'dart:typed_data';

sealed class SyncEventMessage {
  const SyncEventMessage();
}

// need to think of how to do this for relays and non relays.
class SyncEventMessageMain extends SyncEventMessage {
  final int appId;
  final int deviceId;
  final int deviceSequence;
  final Uint8List ciphertext;

  const SyncEventMessageMain({
    required this.appId,
    required this.deviceId,
    required this.deviceSequence,
    required this.ciphertext,
  });
}

/// Visble data that will be sent though a relay, may be not needed with a signal protocol?
/// (as it isolates all data inside the payload)?
/// When recieved by the proxy, it stores it in a persistent queue. Positive ack is only
/// sent once the message have been serialized to disk. Messages should not be ever dropped, or else events wont resolve.
///
/// Is there a need to recover from dropped messages, such as server failure?
/// If anything goes wrong, devices should resync (like send a message of last known message, ask to repeat from there)?
///
/// What if public/private keys known to the relay are always rotated? need some proof to allow forwarding.
///
/// The goal is to prevent strangers sending messages to other users.
///
/// For now this part of the protocol can be ignored, and instead the server
/// just proxies messages to devices, by a public key of each device.
///
/// There is no need to transmit event sequence or deviceId. Also no need for appId,
/// as each app has its own key pair.
class SyncEventMessageToRelay {
  final int sequence; // autoincrement for relay acks
  final Uint8List recieverPubKey; // id of the queue to add messages to
  final Uint8List senderPubKey; // together with proof to do "auth".
  final Uint8List someProofOfAbilityToSendToReciever;
  final Uint8List ciphertext;

  const SyncEventMessageToRelay({
    required this.sequence,
    required this.senderPubKey,
    required this.recieverPubKey,
    required this.someProofOfAbilityToSendToReciever,
    required this.ciphertext,
  });
}

class SyncEventMessageAck {
  final int sequence;

  const SyncEventMessageAck({required this.sequence});
}

/// hhhhhh
class SyncEventMessageNack {
  final int sequence;

  const SyncEventMessageNack({required this.sequence});
}

/// Message data which is sent directly (in real time) between peers.
/// Contents of this message are e2e encrypted in transit.
/// Sequence is for acks
class SyncEventMessageDirect {
  final int sequence;
  final Uint8List cleartext;

  const SyncEventMessageDirect({
    required this.sequence,
    required this.cleartext,
  });
}
