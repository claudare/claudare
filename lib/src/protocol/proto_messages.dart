import 'package:core/src/device_keychain/device_keychain.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/stored_event.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:messagepack/messagepack.dart';

sealed class ProtoAnyMessage {
  const ProtoAnyMessage();

  int get type;
  void pack(Packer p);
  // cant enforce a factory method...
  // ProtoAnyMessage.unpack(Unpacker u);

  static const Map<int, ProtoAnyMessage Function(Unpacker)> _unpackers = {
    ProtoMessagePing.staticType: ProtoMessagePing.unpack,
    ProtoMessageAck.staticType: ProtoMessageAck.unpack,
    ProtoMessageAuth.staticType: ProtoMessageAuth.unpack,
    ProtoMessageClockValue.staticType: ProtoMessageClockValue.unpack,
    ProtoMessageEventValue.staticType: ProtoMessageEventValue.unpack,
  };

  static ProtoAnyMessage unpack(Unpacker u) {
    final type = u.unpackInt();

    if (type == null) {
      throw Exception('bad packed type field: $type');
    }
    if (!_unpackers.containsKey(type)) {
      throw Exception('Unknown message type: $type');
    }

    return _unpackers[type]!(u);
  }
}

class ProtoMessagePing extends ProtoAnyMessage {
  static const staticType = 0;

  const ProtoMessagePing();

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    p.packInt(staticType);
  }

  factory ProtoMessagePing.unpack(Unpacker u) {
    return ProtoMessagePing();
  }

  @override
  String toString() {
    return 'ProtoMessagePing{}';
  }
}

/// [ProtoMessageAuth] provides a way for devices to authenticate with each
/// other. For now, they siply send their DeviceId and it is trusted
class ProtoMessageAuth extends ProtoAnyMessage {
  static const staticType = 1;

  final DeviceClaim claim;

  const ProtoMessageAuth(this.claim);

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    p.packInt(staticType);
    claim.pack(p);
  }

  factory ProtoMessageAuth.unpack(Unpacker u) {
    final claim = DeviceClaim.unpack(u);
    return ProtoMessageAuth(claim);
  }

  @override
  String toString() {
    return 'ProtoMessageAuth{claim: $claim}';
  }
}

/// [ProtoMessageAck] requests the responder to confirm on this whole
/// payload. Ack is sent with the same id back to conform deny. Optional
/// error can be attached, throwing the requester.
class ProtoMessageAck extends ProtoAnyMessage {
  static const staticType = 2;

  final int payloadId;
  final String error;

  const ProtoMessageAck(this.payloadId, this.error);

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    // cheat for now and dont use the packing methods on the DeviceId
    p.packInt(staticType);
    p.packInt(payloadId);
    p.packString(error.isEmpty ? null : error);
  }

  factory ProtoMessageAck.unpack(Unpacker p) {
    final payloadId = p.unpackInt();
    final error = p.unpackString() ?? "";
    return ProtoMessageAck(payloadId!, error);
  }

  @override
  String toString() {
    return 'ProtoMessageAck{payloadId: $payloadId, error: "$error"}';
  }
}

/// [ProtoMessageClockValue] is used for a device to send its latest vector clock.
/// this should include the device id...
class ProtoMessageClockValue extends ProtoAnyMessage {
  static const staticType = 3;

  final EventVectorClock eventClock;

  const ProtoMessageClockValue(this.eventClock);

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    p.packInt(staticType);
    eventClock.pack(p);
  }

  factory ProtoMessageClockValue.unpack(Unpacker u) {
    return ProtoMessageClockValue(EventVectorClock.unpack(u));
  }

  @override
  String toString() {
    return 'ProtoMessageClockValue{eventClock: $eventClock}';
  }
}

/// [ProtoMessageEventValue] is used to send a list of events.
/// either sent by the server in response to a [EventMessageEventQuery].
/// or is sent by client to "upload" events to another server.
class ProtoMessageEventValue extends ProtoAnyMessage {
  static const staticType = 4;

  final StoredEvent event;

  const ProtoMessageEventValue(this.event);

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    p.packInt(staticType);
    event.pack(p);
  }

  factory ProtoMessageEventValue.unpack(Unpacker u) {
    return ProtoMessageEventValue(StoredEvent.unpack(u));
  }

  @override
  String toString() {
    return 'ProtoMessageEventValue{event: $event}';
  }
}

// TODO: blob is implemented here too!
// // [MessageBlobChunkedInit] will initiate the stream by providing base information
// class BlobMessageChunkedInit extends BlobAnyMessage {
//   final BlobId blobId;
//   final int transferId;
//   final int chunkCount;
//   final int totalSizeBytes;
//   final int chunkSizeBytes;
// }

// class BlobMessageChunk extends BlobAnyMessage {
//   final int transferId;
//   final int chunkId;
//   final int chunkSizeBytes;
//   final Uint8List data;
// }

// /// [BlobMessageComplete] will single chunk send data, useful for small blobs
// class BlobMessageComplete extends BlobAnyMessage {
//   final BlobId blobId;
//   final int transferId;
//   final int totalSizeBytes;
//   final Uint8List data;
// }
