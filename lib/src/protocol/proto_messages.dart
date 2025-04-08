import 'dart:typed_data';

import 'package:core/src/event_store/stored_event.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:core/src/event_store/vector_clock_range.dart';
import 'package:messagepack/messagepack.dart';

sealed class ProtoAnyMessage {
  const ProtoAnyMessage();

  int get type;
  void pack(Packer p);
  // cant enforce a factory method...
  // ProtoAnyMessage.unpack(Unpacker u);

  static const Map<int, ProtoAnyMessage Function(Unpacker)> _unpackers = {
    ProtoMessageEmpty.staticType: ProtoMessageEmpty.unpack,
    ProtoMessagePing.staticType: ProtoMessagePing.unpack,
    ProtoMessageClockQuery.staticType: ProtoMessageClockQuery.unpack,
    ProtoMessageClockValue.staticType: ProtoMessageClockValue.unpack,
    ProtoMessageEventQuery.staticType: ProtoMessageEventQuery.unpack,
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

class ProtoMessageEmpty extends ProtoAnyMessage {
  static const staticType = 0;

  const ProtoMessageEmpty();

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    p.packInt(staticType);
  }

  factory ProtoMessageEmpty.unpack(Unpacker u) {
    return ProtoMessageEmpty();
  }
}

class ProtoMessagePing extends ProtoAnyMessage {
  static const staticType = 127;

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
}

/// asking for the latest vector clock
class ProtoMessageClockQuery extends ProtoAnyMessage {
  static const staticType = 1;

  const ProtoMessageClockQuery();

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    p.packInt(staticType);
  }

  factory ProtoMessageClockQuery.unpack(Unpacker u) {
    return ProtoMessageClockQuery();
  }
}

/// [ProtoMessageClockValue] is used for a device to send its latest vector clock.
/// this should include the device id...
class ProtoMessageClockValue extends ProtoAnyMessage {
  static const staticType = 2;

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
}

/// [ProtoMessageEventQuery] asks another device for the events given a
/// cursor and a limit. Reply with type [ProtoMessageEventValue] is expected.
class ProtoMessageEventQuery extends ProtoAnyMessage {
  static const staticType = 3;

  final EventVectorClockRange cursor;
  final int limit;

  const ProtoMessageEventQuery(this.cursor, this.limit);

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    p.packInt(staticType);
    cursor.pack(p);
    p.packInt(limit);
  }

  factory ProtoMessageEventQuery.unpack(Unpacker u) {
    return ProtoMessageEventQuery(
      EventVectorClockRange.unpack(u),
      u.unpackInt()!,
    );
  }
}

/// [ProtoMessageEventValue] is used to send a list of events.
/// either sent by the server in response to a [EventMessageEventQuery].
/// or is sent by client to "upload" events to another server.
class ProtoMessageEventValue extends ProtoAnyMessage {
  static const staticType = 4;

  final List<StoredEvent> events;

  const ProtoMessageEventValue(this.events);

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    p.packInt(staticType);
    p.packListLength(events.length);
    for (final event in events) {
      event.pack(p);
    }
  }

  factory ProtoMessageEventValue.unpack(Unpacker u) {
    final len = u.unpackListLength();

    final out = List<StoredEvent>.generate(
      len,
      (_) => StoredEvent.unpack(u),
      growable: false,
    );

    return ProtoMessageEventValue(out);
  }
}

/// [ProtoMessageForwardData] encapsulates an encrypted message that is sent
/// to another device. The header specify which device it does to, or uses a
/// boardcast. Server is responsible to release these in the same order as the
/// timestamps on the events/blobs. This event type is usually used for
/// bootstrapping new devices. The payloads are encrypted for each other device
/// public key. No broadcast is possible, as communication is private to
/// every other device.
class ProtoMessageForwardData extends ProtoAnyMessage {
  static const staticType = 4;
  final Uint8List ciphertext;

  const ProtoMessageForwardData(this.ciphertext);

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    p.packInt(staticType);
    p.packBinary(ciphertext);
  }

  factory ProtoMessageForwardData.unpack(Unpacker u) {
    return ProtoMessageForwardData(Uint8List.fromList(u.unpackBinary()));
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
