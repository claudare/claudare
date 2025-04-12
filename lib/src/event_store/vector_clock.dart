import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/event_clock.dart';
import 'package:core/src/event_store/id.dart';
import 'package:messagepack/messagepack.dart';

/// Vector clock per device
class EventVectorClock implements Comparable<EventVectorClock> {
  final Map<DeviceId, EventClock> _map;

  const EventVectorClock(this._map);

  factory EventVectorClock.fromEventIds(List<EventId> values) {
    final map = <DeviceId, EventClock>{};
    for (final eventId in values) {
      map[eventId.deviceId] = EventClock.fromEventId(eventId);
    }
    return EventVectorClock(map);
  }

  /// Returns a diff of the clocks. A new range is just a clock
  factory EventVectorClock.diff(EventVectorClock from, EventVectorClock to) {
    final out = <DeviceId, EventClock>{};

    for (final toEntry in to._map.entries) {
      final deviceId = toEntry.key;
      final toEventClock = toEntry.value;

      final fromEventClock = from._map[deviceId];

      if (fromEventClock == null) {
        // clock needs to start at zero
        out[deviceId] = EventClock.zero();
        continue;
      }

      if (fromEventClock.compareTo(toEventClock) < 0) {
        // if our clock is less, we must use it
        out[deviceId] = fromEventClock;
      }
    }

    return EventVectorClock(out);
  }

  EventVectorClock.empty() : _map = {};

  EventId? operator [](DeviceId deviceId) {
    final eventClock = _map[deviceId];

    if (eventClock == null) {
      return null;
    }

    return EventId(eventClock.timestamp, eventClock.sequence, deviceId);
  }

  // Iterable<MapEntry<DeviceId, Timestamp>> get mapEntries =>
  //     UnmodifiableMapView(_mapDeviceTimestamp).entries;

  Iterable<EventId> get entries => _map.entries.map(
    (entry) => EventId(entry.value.timestamp, entry.value.sequence, entry.key),
  );

  int get length => _map.length;

  void update(EventId id) {
    // must check that older events are never inserted.
    // replication is strict from old to new
    final currentEventClock = _map[id.deviceId];

    if (currentEventClock != null &&
        id.timestamp < currentEventClock.timestamp) {
      throw Exception(
        'New event timestamp is behind the latest known event. Latest ${currentEventClock.timestamp.toPrettyString()}, got  ${id.timestamp.toPrettyString()} instead.',
      );
    }

    if (currentEventClock != null &&
        id.sequence != currentEventClock.sequence + 1) {
      throw Exception(
        'New event sequence is out of order. Latest ${currentEventClock.sequence}, got ${id.sequence} instead.',
      );
    }

    // check that order is correct

    _map[id.deviceId] = EventClock.fromEventId(id);
  }

  @Deprecated('do not use, it does not work as intended')
  EventVectorClock copyWith(Map<DeviceId, EventClock> map) {
    // merge the new map into the existing one
    // make sure to actually copy everything, as to not get shot by mutability
    final newMap = Map<DeviceId, EventClock>.from(_map);
    newMap.addAll(map);
    return EventVectorClock(newMap);
  }

  EventVectorClock clone() {
    final copy = Map<DeviceId, EventClock>.from(_map);
    return EventVectorClock(copy);
  }

  @override
  int compareTo(EventVectorClock other) {
    if (_map.length != other._map.length) {
      // vector clock with more devices is newer
      return _map.length.compareTo(other._map.length);
    }

    for (final entry in _map.entries) {
      final otherTs = other._map[entry.key];
      if (otherTs == null) {
        return 1;
      }
      final cmp = entry.value.compareTo(otherTs);
      if (cmp != 0) {
        return cmp;
      }
    }

    return 0;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is EventVectorClock && compareTo(other) == 0;
  }

  @override
  int get hashCode => _map.hashCode;

  // return a map with device ids as keys and timestamps as values
  // Map<String, dynamic> toJson() {
  //   final out = <String, String>{};

  //   for (final entry in _map.entries) {
  //     out[entry.key.toString()] = entry.value.toString();
  //   }

  //   return out;
  // }

  // factory EventVectorClock.fromJson(Map<String, dynamic> json) {
  //   // iterate over the json and assign keys and values
  //   final out = <DeviceId, Timestamp>{};

  //   for (final entry in json.entries) {
  //     out[DeviceId.fromString(entry.key)] = Timestamp.fromString(entry.value);
  //   }

  //   return EventVectorClock(out);
  // }

  // @override
  // String toString() {
  //   return 'EventVectorClock{${_map.entries.map((e) => '${e.key}: ${e.value.toISO8601()}').join(', ')}}';
  // }

  void pack(Packer p) {
    p.packMapLength(_map.length);
    _map.forEach((key, value) {
      key.pack(p);
      value.pack(p);
    });
  }

  factory EventVectorClock.unpack(Unpacker u) {
    final out = <DeviceId, EventClock>{};

    final len = u.unpackMapLength();
    for (int i = 0; i < len; i++) {
      out[DeviceId.unpack(u)] = EventClock.unpack(u);
    }

    return EventVectorClock(out);
  }
}
