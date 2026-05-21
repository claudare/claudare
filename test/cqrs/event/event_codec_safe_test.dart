import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:core/cqrs.dart';
import 'package:core/src/cqrs/event/event_codec_safe.dart';
import 'package:core/utils.dart';

class TestEvent {
  String str;

  TestEvent({required this.str});
}

class TestCodec implements EventCodec<TestEvent> {
  @override
  EncodedEvent encode(event) {
    return EncodedEvent(
      kind: 'test',
      bytes: JsonConverter.encode({'str': event.str}),
    );
  }

  @override
  decode(EncodedEvent encoded) {
    if (encoded.kind == 'fatal') {
      throw ArgumentError('Intentially fatal error');
    }

    final map = JsonConverter.decode(encoded.bytes);
    return TestEvent(str: map['str'] as String);
  }
}

void main() {
  group('Event codec safe', () {
    late EventCodecSafe<TestEvent> safe;

    setUp(() async {
      safe = EventCodecSafe(TestCodec());
    });

    // simple all in one test
    test('json roundtrip okay', () {
      final og = TestEvent(str: "okay");

      final encoded = safe.encode(og);
      final decoded = safe.decode(encoded);

      expect(decoded.str, equals(og.str));
    });

    test('json decode error', () {
      final encoded = EncodedEvent(
        kind: 'fatal',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      // expect that it throws passes the error along
      expect(() => safe.decode(encoded), throwsArgumentError);
    });

    test('json decode exception-like error', () {
      final encoded = EncodedEvent(
        kind: 'test',
        bytes: JsonConverter.encode({"str": 123}), // number instead of string
      );

      expect(() => safe.decode(encoded), throwsA(isA<EventCodecException>()));
    });
  });
}
