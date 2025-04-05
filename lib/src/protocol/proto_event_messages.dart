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
    // EventMessageEventQuery._type: (up) => EventMessageEventQuery.unpack(up),
    // EventMessageEventValue._type: (up) => EventMessageEventValue.unpack(up),
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
// TODO all thouse too
// class EventMessageEventQuery extends ProtoEventAnyMessage {
//   static const _type = 'event_query';

//   final EventVectorClockRange cursor;
//   final int limit;

//   const EventMessageEventQuery(this.cursor, this.limit);

//   @override
//   Map<String, dynamic> toJson() {
//     return {'_type': _type, 'cursor': cursor.toJson(), 'limit': limit};
//   }

//   factory EventMessageEventQuery.pack(Map<String, dynamic> json) {
//     return EventMessageEventQuery(
//       EventVectorClockRange.pack(json['cursor']),
//       json['limit'],
//     );
//   }
// }

// /// [EventMessageEventValue] is used to send a list of events.
// /// either sent by the server in response to a [EventMessageEventQuery].
// /// or is sent by client to "upload" events to another server.
// class EventMessageEventValue extends ProtoEventAnyMessage {
//   static const _type = 'event_value';

//   final List<StoredEvent> events;

//   const EventMessageEventValue(this.events);

//   @override
//   Map<String, dynamic> toJson() {
//     return {'_type': _type, 'events': events.map((e) => e.toJson()).toList()};
//   }

//   factory EventMessageEventValue.pack(Map<String, dynamic> json) {
//     return EventMessageEventValue(
//       (json['events'] as List<dynamic>)
//           .map((e) => StoredEvent.pack(e))
//           .toList(),
//     );
//   }
// }
