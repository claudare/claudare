// simple event clock to get the "latest known value from each device"
import 'dart:collection';

import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/id.dart';
import 'package:core/src/timestamp.dart';

class EventClock implements Comparable<EventClock> {
  final Map<DeviceId, Timestamp> _mapDeviceTimestamp;

  const EventClock(this._mapDeviceTimestamp);

  EventId operator [](DeviceId deviceId) {
    final ts = _mapDeviceTimestamp[deviceId];

    if (ts == null) {
      throw Exception('unknown device id $deviceId, not in VectorClock');
    }

    return EventId(ts, deviceId);
  }

  Iterable<MapEntry<DeviceId, Timestamp>> get entries =>
      UnmodifiableMapView(_mapDeviceTimestamp).entries;

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

  @override
  String toString() {
    return 'EventVectorClock{${_mapDeviceTimestamp.entries.map((e) => '${e.key}: ${e.value.toISO8601()}').join(', ')}}';
  }
}
