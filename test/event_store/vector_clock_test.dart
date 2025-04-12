import 'package:core/src/event_store/event_clock.dart';
import 'package:core/src/event_store/id.dart';
import 'package:test/test.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/timestamp.dart';

void main() {
  group('EventClock', () {
    DeviceId deviceId1 = DeviceId(1);
    DeviceId deviceId2 = DeviceId(2);

    test('initialization', () {
      final clock = EventVectorClock({});
      expect(clock.length == 0, isTrue);
    });

    test('update event to next one', () {
      final clock = EventVectorClock({
        deviceId1: EventClock(Timestamp(1000), 1),
      });
      clock.update(EventId(Timestamp(2000), 2, deviceId1));
      expect(clock[deviceId1], equals(EventId(Timestamp(2000), 2, deviceId1)));
    });

    test('update event from an unknown device', () {
      final clock = EventVectorClock({
        deviceId1: EventClock(Timestamp(1000), 1),
      });
      clock.update(EventId(Timestamp(1000), 1, deviceId2));
      expect(clock.length, equals(2));
      expect(clock[deviceId2], equals(EventId(Timestamp(1000), 1, deviceId2)));
    });

    test(
      'update event that has timestamp behind the latest known timestamp',
      () {
        final clock = EventVectorClock({
          deviceId1: EventClock(Timestamp(2000), 1),
        });
        // here the sequence id is correct
        expect(
          () => clock.update(EventId(Timestamp(1000), 2, deviceId1)),
          throwsException,
        );
      },
    );

    test('update event that has bad sequence id', () {
      final clock = EventVectorClock({
        deviceId1: EventClock(Timestamp(1000), 1),
      });

      expect(
        () => clock.update(EventId(Timestamp(2000), 3, deviceId1)),
        throwsException,
      );
    });

    test('compare equal EventClocks', () {
      final clock1 = EventVectorClock({
        deviceId1: EventClock(Timestamp(1000), 1),
        deviceId2: EventClock(Timestamp(2000), 1),
      });
      final clock2 = EventVectorClock({
        deviceId1: EventClock(Timestamp(1000), 1),
        deviceId2: EventClock(Timestamp(2000), 1),
      });
      expect(clock1.compareTo(clock2), equals(0));
    });

    test('compare EventClocks with a different number of devices', () {
      final clock1 = EventVectorClock({
        deviceId1: EventClock(Timestamp(1000), 1),
        deviceId2: EventClock(Timestamp(1000), 1),
      });
      final clock2 = EventVectorClock({
        deviceId1: EventClock(Timestamp(1000), 1),
      });
      expect(clock1.compareTo(clock2), equals(1));
    });

    test('compare two EventClocks with different timestamps', () {
      final clock1 = EventVectorClock({
        deviceId1: EventClock(Timestamp(1000), 1),
      });
      final clock2 = EventVectorClock({
        deviceId1: EventClock(Timestamp(2000), 2),
      });
      expect(clock1.compareTo(clock2), equals(-1));
    });

    test('diffing the clocks', () {
      final deviceId3 = DeviceId(3);
      final local = EventVectorClock({
        deviceId1: EventClock(Timestamp(100), 1),
        deviceId2: EventClock(Timestamp(20), 1),
        deviceId3: EventClock(Timestamp(50), 1),
      });
      final remote = EventVectorClock({
        deviceId1: EventClock(Timestamp(10), 1),
        deviceId2: EventClock(Timestamp(200), 1),
      });

      final localToRemote = EventVectorClock.diff(local, remote);
      expect(localToRemote[deviceId1], isNull);
      expect(localToRemote[deviceId2], EventId(Timestamp(20), 1, deviceId2));
      expect(localToRemote[deviceId3], isNull);

      final remoteToLocal = EventVectorClock.diff(remote, local);
      expect(remoteToLocal[deviceId1], EventId(Timestamp(10), 1, deviceId1));
      expect(remoteToLocal[deviceId2], isNull);
      expect(remoteToLocal[deviceId3], EventId(Timestamp(0), 0, deviceId3));
    });
  });
}
