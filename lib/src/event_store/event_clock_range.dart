// an event vector clock but instead holding a value, it holds a range of values

import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/event_clock.dart';
import 'package:core/src/event_store/event_id.dart';
import 'package:core/src/timestamp.dart';

class TimestampRange {
  final Timestamp start;
  final Timestamp end;

  TimestampRange(this.start, this.end) : assert(end > start);

  Map<String, dynamic> toJson() {
    return {'start': start.toJson(), 'end': end.toJson()};
  }

  factory TimestampRange.fromJson(Map<String, dynamic> json) {
    return TimestampRange(
      Timestamp.fromJson(json['start']),
      Timestamp.fromJson(json['end']),
    );
  }
}

class EventClockRange {
  final Map<DeviceId, TimestampRange> ranges;

  const EventClockRange(this.ranges);

  /// creates a range from clocks, inclusive of the start value
  /// this means that the start value must be skipped when querying.
  /// next timestamp will be assumed
  factory EventClockRange.betweenClocks(EventClock from, EventClock to) {
    final Map<DeviceId, TimestampRange> ranges = {};
    // if from value is less or equal to to value, it does not get included
    // when to has a value which is missing from from, then it starts at 0
    // when from has a value which is missing from to, then it ends at max

    for (final toEventId in to.entries) {
      final deviceId = toEventId.deviceId;
      final fromEntry = from[deviceId];

      // if no from entry, its an empty one
      if (fromEntry == null) {
        ranges[deviceId] = TimestampRange(
          Timestamp.zero(),
          toEventId.timestamp,
        );
        continue;
      }
      final nextStart = fromEntry.timestamp;
      if (toEventId.timestamp > nextStart) {
        ranges[deviceId] = TimestampRange(nextStart, toEventId.timestamp);
      }
    }

    return EventClockRange(ranges);
  }

  factory EventClockRange.fromStart(EventClock to) {
    return EventClockRange.betweenClocks(EventClock({}), to);
  }

  TimestampRange? operator [](DeviceId deviceId) => ranges[deviceId];

  int get length => ranges.length;

  bool get isEmpty => ranges.isEmpty;

  void advanceById(EventId id) {
    final deviceId = id.deviceId;
    final timestamp = id.timestamp;

    final thisRange = ranges[deviceId];

    if (thisRange == null) {
      throw Exception('advancing range cannot define new device: $deviceId');
    }
    if (thisRange.start > timestamp) {
      throw Exception('advancing range cannot go back');
    }

    if (thisRange.end <= timestamp) {
      // remove it if caught up
      ranges.remove(deviceId);
    } else {
      ranges[deviceId] = TimestampRange(timestamp, thisRange.end);
    }
  }

  /// dont use this, instead advance by id after new events are added
  void advanceByClock(EventClock to) {
    for (final eventId in to.entries) {
      advanceById(eventId);
    }
  }

  // to from json
  factory EventClockRange.fromJson(Map<String, dynamic> json) {
    final Map<DeviceId, TimestampRange> ranges = {};
    for (final entry in json.entries) {
      final deviceId = DeviceId.fromString(entry.key);
      final rangeJson = entry.value as Map<String, dynamic>;
      ranges[deviceId] = TimestampRange.fromJson(rangeJson);
    }
    return EventClockRange(ranges);
  }

  // to json
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {};
    for (final entry in ranges.entries) {
      json[entry.key.toString()] = entry.value.toJson();
    }
    return json;
  }
}
