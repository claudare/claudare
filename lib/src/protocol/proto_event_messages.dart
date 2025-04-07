import 'package:core/src/event_store/stored_event.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:core/src/event_store/vector_clock_range.dart';
import 'package:messagepack/messagepack.dart';

sealed class ProtoEventAnyMessage {
  const ProtoEventAnyMessage();

  void pack(Packer p);
  ProtoEventAnyMessage.unpack(Unpacker u);

  static final Map<int, ProtoEventAnyMessage Function(Unpacker)> _unpackers = {
    ProtoEventMessageClockQuery._type:
        (up) => ProtoEventMessageClockQuery.unpack(up),
    ProtoEventMessageClockValue._type:
        (up) => ProtoEventMessageClockValue.unpack(up),
    ProtoEventMessageEventQuery._type:
        (up) => ProtoEventMessageEventQuery.unpack(up),
    ProtoEventMessageEventValue._type:
        (up) => ProtoEventMessageEventValue.unpack(up),
  };

  static ProtoEventAnyMessage anyUnpack(Unpacker u) {
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

class ProtoEventMessageEmpty extends ProtoEventAnyMessage {
  const ProtoEventMessageEmpty();

  factory ProtoEventMessageEmpty.unpack(Unpacker u) {
    return ProtoEventMessageEmpty();
  }

  @override
  void pack(Packer p) {
    throw Exception("empty message is not packable");
  }
}

/// asking for the latest vector clock
class ProtoEventMessageClockQuery extends ProtoEventAnyMessage {
  static const _type = 1;

  const ProtoEventMessageClockQuery();

  factory ProtoEventMessageClockQuery.unpack(Unpacker u) {
    return ProtoEventMessageClockQuery();
  }

  @override
  void pack(Packer p) {
    p.packInt(_type);
  }
}

/// [ProtoEventMessageClockValue] is used for a device to send its latest vector clock.
/// this should include the device id...
class ProtoEventMessageClockValue extends ProtoEventAnyMessage {
  static const _type = 2;

  final EventVectorClock eventClock;

  const ProtoEventMessageClockValue(this.eventClock);

  factory ProtoEventMessageClockValue.unpack(Unpacker u) {
    return ProtoEventMessageClockValue(EventVectorClock.unpack(u));
  }

  @override
  void pack(Packer p) {
    p.packInt(_type);
    eventClock.pack(p);
  }
}

// conver to use a pack method
class ProtoEventMessageEventQuery extends ProtoEventAnyMessage {
  static const _type = 3;

  final EventVectorClockRange cursor;
  final int limit;

  const ProtoEventMessageEventQuery(this.cursor, this.limit);

  // hello??
  @override
  void pack(Packer p) {
    p.packInt(_type);
    cursor.pack(p);
    p.packInt(limit);
  }

  factory ProtoEventMessageEventQuery.unpack(Unpacker u) {
    return ProtoEventMessageEventQuery(
      EventVectorClockRange.unpack(u),
      u.unpackInt()!,
    );
  }
}

/// [ProtoEventMessageEventValue] is used to send a list of events.
/// either sent by the server in response to a [EventMessageEventQuery].
/// or is sent by client to "upload" events to another server.
class ProtoEventMessageEventValue extends ProtoEventAnyMessage {
  static const _type = 4;

  final List<StoredEvent> events;

  const ProtoEventMessageEventValue(this.events);

  @override
  void pack(Packer p) {
    p.packInt(_type);
    p.packListLength(events.length);
    for (final event in events) {
      event.pack(p);
    }
  }

  factory ProtoEventMessageEventValue.unpack(Unpacker u) {
    final len = u.unpackListLength();

    final out = List<StoredEvent>.generate(
      len,
      (_) => StoredEvent.unpack(u),
      growable: false,
    );

    return ProtoEventMessageEventValue(out);
  }
}
