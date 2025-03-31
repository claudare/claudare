import 'package:test/test.dart';
import 'package:core/src/event_store/event_clock.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/event_id.dart';
import 'package:core/src/timestamp.dart';

void main() {
  group('EventClock', () {
    DeviceId deviceId1 = DeviceId(1);
    Timestamp timestamp1 = Timestamp(1000);
    DeviceId deviceId2 = DeviceId(2);
    Timestamp timestamp2 = Timestamp(1001);

    test('initialization', () {
      final clock = EventClock({});
      expect(clock.length == 0, isTrue);
    });

    test('update event from a known device', () {
      final clock = EventClock({deviceId1: timestamp1});
      clock.update(EventId(timestamp2, deviceId1));
      expect(clock[deviceId1], equals(EventId(timestamp2, deviceId1)));
    });

    test('update event from an unknown device', () {
      final clock = EventClock({deviceId1: timestamp1});
      clock.update(EventId(timestamp2, deviceId2));
      expect(clock[deviceId2], equals(EventId(timestamp2, deviceId2)));
    });

    test('update event that is behind the latest known event', () {
      final clock = EventClock({deviceId1: timestamp2});
      expect(
        () => clock.update(EventId(timestamp1, deviceId1)),
        throwsException,
      );
    });

    test('compare two EventClocks with the same deviceTimestamp map', () {
      final clock1 = EventClock({deviceId1: timestamp1, deviceId2: timestamp2});
      final clock2 = EventClock({deviceId1: timestamp1, deviceId2: timestamp2});
      expect(clock1.compareTo(clock2), equals(0));
    });

    test('compare two EventClocks with a different number of devices', () {
      final clock1 = EventClock({deviceId1: timestamp1, deviceId2: timestamp2});
      final clock2 = EventClock({deviceId1: timestamp1});
      expect(clock1.compareTo(clock2), equals(1));
    });

    test('compare two EventClocks with different timestamps', () {
      final clock1 = EventClock({deviceId1: timestamp1});
      final clock2 = EventClock({deviceId1: timestamp2});
      expect(clock1.compareTo(clock2), equals(-1));
    });
  });
}
