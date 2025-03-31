import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:core/src/event_store/vector_clock_range.dart';
import 'package:core/src/event_store/id.dart';
import 'package:core/src/timestamp.dart';
import 'package:test/test.dart';

void main() {
  group('EventClockRange', () {
    final deviceA = DeviceId(1);
    final deviceB = DeviceId(2);
    final deviceC = DeviceId(3);
    final deviceD = DeviceId(4);

    final from = EventVectorClock.fromEntries([
      EventId(Timestamp(100), deviceA),
      EventId(Timestamp(500), deviceB),
      EventId(Timestamp(1000), deviceC),
    ]);

    final to = EventVectorClock.fromEntries([
      EventId(Timestamp(1000), deviceA),
      EventId(Timestamp(500), deviceB),
      EventId(Timestamp(100), deviceC),
      EventId(Timestamp(50), deviceD),
    ]);

    test('creates from 2 vector clocks', () {
      final range = EventVectorClockRange.betweenClocks(from, to);

      expect(range[deviceA]!.start, Timestamp(100));
      expect(range[deviceA]!.end, Timestamp(1000));

      expect(range[deviceB], isNull);
      expect(range[deviceC], isNull);

      expect(range[deviceD]!.start, Timestamp(0));
      expect(range[deviceD]!.end, Timestamp(50));
    });

    test('advances the range', () {
      final range = EventVectorClockRange.betweenClocks(from, to);

      final newClock = EventVectorClock.fromEntries([
        EventId(Timestamp(1000), deviceA),
        EventId(Timestamp(25), deviceD),
      ]);

      range.advanceByClock(newClock);

      // A is removed as reached the last value
      expect(range[deviceA], isNull);

      expect(range[deviceD]!.start, Timestamp(25));
      expect(range[deviceD]!.end, Timestamp(50));
    });
  });
}
