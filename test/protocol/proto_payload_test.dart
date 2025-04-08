import 'package:core/device_keychain.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:core/src/protocol/proto_payload.dart';
import 'package:core/src/protocol/proto_headers.dart';
import 'package:core/src/protocol/proto_messages.dart';
import 'package:core/src/timestamp.dart';
import 'package:test/test.dart';

void main() {
  group('ProtoPayload', () {
    test(' serialization', () {
      final payload = ProtoPayload(
        {},
        ProtoMessageClockValue(
          EventVectorClock({DeviceId(0): Timestamp(2000)}),
        ),
      );
      payload.setHeader(
        ProtoHeaderAuth(DeviceClaim(DeviceId(0), DeviceId(1000))),
      );

      final bin = payload.pack();

      final out = ProtoPayload.unpack(bin);

      expect(out.version, equals(0));
      expect(payload.getAuth().claim.fromDeviceId, equals(DeviceId(0)));
      expect(
        (payload.data as ProtoMessageClockValue).eventClock,
        equals(EventVectorClock({DeviceId(0): Timestamp(2000)})),
      );

      expect(payload.getAck(), isNull);
    });
  });
}
