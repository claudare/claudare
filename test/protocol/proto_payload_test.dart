import 'package:test/test.dart';
import 'package:core/core.dart';
import 'package:core/event_store.dart';
import 'package:core/protocol.dart';

void main() {
  group('ProtoPayload', () {
    test('serialization (INCOMPLETE!)', () {
      final eventClock = EventVectorClock.fromEventIds([
        EventId(Timestamp(2000), 1, DeviceId(0)),
      ]);
      final payload = ProtoPayload(1, ProtoMessageClockValue(eventClock));

      final bin = payload.toBytes();
      final out = ProtoPayload.fromBytes(bin);
      expect(out.id, equals(1));
      expect(
        (out.data as ProtoMessageClockValue).eventClock,
        equals(eventClock),
      );
    });
  });
}
