import 'package:core/src/event_store/stored_event.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:core/src/event_store/vector_clock_range.dart';
import 'package:messagepack/messagepack.dart';

sealed class ProtoAnyMessage {
  const ProtoAnyMessage();

  void pack(Packer p);
  // cant enforce a factory method...
  // ProtoAnyMessage.unpack(Unpacker u);

  static const Map<int, ProtoAnyMessage Function(Unpacker)> _unpackers = {
    ProtoMessageClockQuery._type: ProtoMessageClockQuery.unpack,
    ProtoMessageClockValue._type: ProtoMessageClockValue.unpack,
    ProtoMessageEventQuery._type: ProtoMessageEventQuery.unpack,
    ProtoMessageEventValue._type: ProtoMessageEventValue.unpack,
  };

  static ProtoAnyMessage anyUnpack(Unpacker u) {
    final type = u.unpackInt();

    if (type == null || type == 0) {
      throw Exception('bad packed type field: $type');
    }
    if (!_unpackers.containsKey(type)) {
      throw Exception('Unknown message type: $type');
    }

    return _unpackers[type]!(u);
  }
}

class ProtoMessageEmpty extends ProtoAnyMessage {
  const ProtoMessageEmpty();

  factory ProtoMessageEmpty.unpack(Unpacker u) {
    return ProtoMessageEmpty();
  }

  @override
  void pack(Packer p) {
    throw Exception("empty message is not packable");
  }
}

/// asking for the latest vector clock
class ProtoMessageClockQuery extends ProtoAnyMessage {
  static const _type = 1;

  const ProtoMessageClockQuery();

  factory ProtoMessageClockQuery.unpack(Unpacker u) {
    return ProtoMessageClockQuery();
  }

  @override
  void pack(Packer p) {
    p.packInt(_type);
  }
}

/// [ProtoMessageClockValue] is used for a device to send its latest vector clock.
/// this should include the device id...
class ProtoMessageClockValue extends ProtoAnyMessage {
  static const _type = 2;

  final EventVectorClock eventClock;

  const ProtoMessageClockValue(this.eventClock);

  factory ProtoMessageClockValue.unpack(Unpacker u) {
    return ProtoMessageClockValue(EventVectorClock.unpack(u));
  }

  @override
  void pack(Packer p) {
    p.packInt(_type);
    eventClock.pack(p);
  }
}

/// [ProtoMessageEventQuery] asks another device for the events given a
/// cursor and a limit. Reply with type [ProtoMessageEventValue] is expected.
class ProtoMessageEventQuery extends ProtoAnyMessage {
  static const _type = 3;

  final EventVectorClockRange cursor;
  final int limit;

  const ProtoMessageEventQuery(this.cursor, this.limit);

  @override
  void pack(Packer p) {
    p.packInt(_type);
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
  static const _type = 4;

  final List<StoredEvent> events;

  const ProtoMessageEventValue(this.events);

  @override
  void pack(Packer p) {
    p.packInt(_type);
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
