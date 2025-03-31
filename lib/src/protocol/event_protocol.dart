// this is the communication protocol definition
// the server must be kept stateless. And every single client should be able
// to act as a server or as a client

import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/stored_event.dart';
import 'package:core/src/event_store/event_clock.dart';
import 'package:core/src/event_store/event_clock_range.dart';

typedef PaloadId = int;

class EventPayload {
  // id of the message to multiplex messages over a single connection
  PaloadId payloadId;
  List<EventAnyMessage> messages;

  EventPayload(this.payloadId, this.messages);

  Map<String, dynamic> toJson() {
    return {
      'id': payloadId,
      'messages': messages.map((message) => message.toJson()).toList(),
    };
  }

  factory EventPayload.fromJson(Map<String, dynamic> json) {
    return EventPayload(
      json['id'],
      json['messages']
          .map((message) => EventAnyMessage.anyFromJson(message))
          .toList(),
    );
  }
}

sealed class EventAnyMessage {
  const EventAnyMessage();

  Map<String, dynamic> toJson();
  EventAnyMessage.fromJson(Map<String, dynamic> json);

  static final Map<String, EventAnyMessage Function(Map<String, dynamic>)>
  _parsers = {
    EventMessageAck._type: (json) => EventMessageAck.fromJson(json),
    EventMessageAuth._type: (json) => EventMessageAuth.fromJson(json),
    EventMessageClockQuery._type:
        (json) => EventMessageClockQuery.fromJson(json),
    EventMessageClockValue._type:
        (json) => EventMessageClockValue.fromJson(json),
    EventMessageEventQuery._type:
        (json) => EventMessageEventQuery.fromJson(json),
    EventMessageEventValue._type:
        (json) => EventMessageEventValue.fromJson(json),
  };

  static EventAnyMessage anyFromJson(Map<String, dynamic> json) {
    if (_parsers.containsKey(json['_type'])) {
      return _parsers[json['_type']]!(json);
    }
    throw Exception('Unknown message type: ${json['_type']}');
  }
}

/// [EventMessageAck] acknowledges that whatever payload was received in good order
/// and that they were written to disk. Client doesnt really need to ack to server.
/// But server should ack. does it ack on the payload id (to confirm whole payload is good )
class EventMessageAck extends EventAnyMessage {
  static const _type = 'ack';

  final PaloadId payloadId;

  const EventMessageAck(this.payloadId);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'payloadId': payloadId};
  }

  factory EventMessageAck.fromJson(Map<String, dynamic> json) {
    return EventMessageAck(json['payloadId'] as int);
  }
}

/// request/response for authentication
/// for now we just trust the device id
/// in proper implementation this uses cryptographic signatures to verify
/// that this device can read/write. Will try to avoid static sessions?
/// client also receives this message from the server to verify a remote device.
class EventMessageAuth extends EventAnyMessage {
  static const _type = 'auth';

  final DeviceId deviceId;

  const EventMessageAuth(this.deviceId);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'deviceId': deviceId.toString()};
  }

  factory EventMessageAuth.fromJson(Map<String, dynamic> json) {
    return EventMessageAuth(DeviceId.fromString(json['deviceId']));
  }
}

/// asking for the latest vector clock
class EventMessageClockQuery extends EventAnyMessage {
  static const _type = 'clock_query';

  const EventMessageClockQuery();

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type};
  }

  factory EventMessageClockQuery.fromJson(Map<String, dynamic> json) {
    return EventMessageClockQuery();
  }
}

/// [EventMessageClockValue] is used to send the latest vector clock.
/// TODO: should this include device id?
class EventMessageClockValue extends EventAnyMessage {
  static const _type = 'clock_value';

  final EventClock eventClock;

  const EventMessageClockValue(this.eventClock);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'eventClock': eventClock.toJson()};
  }

  factory EventMessageClockValue.fromJson(Map<String, dynamic> json) {
    return EventMessageClockValue(EventClock.fromJson(json['eventClock']));
  }
}

class EventMessageEventQuery extends EventAnyMessage {
  static const _type = 'event_query';

  final EventClockRange cursor;
  final int limit;

  const EventMessageEventQuery(this.cursor, this.limit);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'cursor': cursor.toJson(), 'limit': limit};
  }

  factory EventMessageEventQuery.fromJson(Map<String, dynamic> json) {
    return EventMessageEventQuery(
      EventClockRange.fromJson(json['cursor']),
      json['limit'],
    );
  }
}

/// [EventMessageEventValue] is used to send a list of events.
/// either sent by the server in response to a [EventMessageEventQuery].
/// or is sent by client to "upload" events to another server.
class EventMessageEventValue extends EventAnyMessage {
  static const _type = 'event_value';

  final List<StoredEvent> events;

  const EventMessageEventValue(this.events);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'events': events.map((e) => e.toJson()).toList()};
  }

  factory EventMessageEventValue.fromJson(Map<String, dynamic> json) {
    return EventMessageEventValue(
      (json['events'] as List<dynamic>)
          .map((e) => StoredEvent.fromJson(e))
          .toList(),
    );
  }
}
