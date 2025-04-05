import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:core/src/protocol/proto_event.dart';
import 'package:core/src/protocol/proto_event_headers.dart';
import 'package:core/src/protocol/proto_event_messages.dart';
import 'package:core/src/timestamp.dart';
import 'package:test/test.dart';

void main() {
  group('ProtoEvent', () {
    test('ProtoEventPayload serialization', () {
      final payload = ProtoEventPayload(
        [ProtoEventHeaderAuth(DeviceId(0))],
        [
          ProtoEventMessageClockValue(
            EventVectorClock({DeviceId(0): Timestamp(2000)}),
          ),
        ],
      );

      final bin = payload.pack();

      final out = ProtoEventPayload.unpack(bin);

      expect(out.version, equals(0));
      expect(
        (payload.headers.first as ProtoEventHeaderAuth).deviceId,
        equals(DeviceId(0)),
      );
      expect(
        (payload.messages.first as ProtoEventMessageClockValue).eventClock,
        equals(EventVectorClock({DeviceId(0): Timestamp(2000)})),
      );
    });
  });
}
