import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/event_id.dart';
import 'package:core/src/timestamp.dart';

class EventClock implements Comparable<EventClock> {
  final Map<DeviceId, Timestamp> _mapDeviceTimestamp;

  const EventClock(this._mapDeviceTimestamp);

  factory EventClock.fromEntries(List<EventId> values) {
    final map = <DeviceId, Timestamp>{};
    for (final eventId in values) {
      map[eventId.deviceId] = eventId.timestamp;
    }
    return EventClock(map);
  }

  EventId? operator [](DeviceId deviceId) {
    final ts = _mapDeviceTimestamp[deviceId];

    if (ts == null) {
      return null;
    }

    return EventId(ts, deviceId);
  }

  // Iterable<MapEntry<DeviceId, Timestamp>> get mapEntries =>
  //     UnmodifiableMapView(_mapDeviceTimestamp).entries;

  Iterable<EventId> get entries => _mapDeviceTimestamp.entries.map(
    (entry) => EventId(entry.value, entry.key),
  );

  int get length => _mapDeviceTimestamp.length;

  void update(EventId id) {
    // must check that older events are never inserted.
    // replication is strict from old to new
    final currentTs = _mapDeviceTimestamp[id.deviceId];

    if (currentTs != null && id.timestamp <= currentTs) {
      throw Exception(
        'New event is behind the latest known event. Latest ${id.timestamp.toISO8601()}, got ${currentTs.toISO8601()} instead.',
      );
    }

    _mapDeviceTimestamp[id.deviceId] = id.timestamp;
  }

  EventClock copyWith(Map<DeviceId, Timestamp> map) {
    // merge the new map into the existing one
    // make sure to actually copy everything, as to not get shot by mutability
    final newMap = Map<DeviceId, Timestamp>.from(_mapDeviceTimestamp);
    newMap.addAll(map);
    return EventClock(newMap);
  }

  @override
  int compareTo(EventClock other) {
    if (_mapDeviceTimestamp.length != other._mapDeviceTimestamp.length) {
      // vector clock with more devices is newer
      return _mapDeviceTimestamp.length.compareTo(
        other._mapDeviceTimestamp.length,
      );
    }

    for (final entry in _mapDeviceTimestamp.entries) {
      final otherTs = other._mapDeviceTimestamp[entry.key];
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

    return other is EventClock && compareTo(other) == 0;
  }

  @override
  int get hashCode => _mapDeviceTimestamp.hashCode;

  // return a map with device ids as keys and timestamps as values
  Map<String, dynamic> toJson() {
    final out = <String, String>{};

    for (final entry in _mapDeviceTimestamp.entries) {
      out[entry.key.toString()] = entry.value.toJson();
    }

    return out;
  }

  factory EventClock.fromJson(Map<String, dynamic> json) {
    // iterate over the json and assign keys and values
    final out = <DeviceId, Timestamp>{};

    for (final entry in json.entries) {
      out[DeviceId.fromString(entry.key)] = Timestamp.fromJson(entry.value);
    }

    return EventClock(out);
  }

  @override
  String toString() {
    return 'EventVectorClock{${_mapDeviceTimestamp.entries.map((e) => '${e.key}: ${e.value.toISO8601()}').join(', ')}}';
  }
}
