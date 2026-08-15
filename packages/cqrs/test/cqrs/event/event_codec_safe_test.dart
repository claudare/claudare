import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/event/event_codec_safe.dart';
import 'package:common/common.dart';

class TestEvent {
  String str;

  TestEvent({required this.str});
}

class TestCodec implements EventCodec<TestEvent> {
  @override
  EncodedEvent encode(event) {
    if (event.str == 'fatal') {
      throw StateError('intentionally fatal error');
    }
    return EncodedEvent(
      kind: 'test',
      bytes: JsonConverter.encode({'str': event.str}),
    );
  }

  @override
  decode(EncodedEvent encoded) {
    if (encoded.kind == 'fatal') {
      throw ArgumentError('intentionally fatal error');
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
      final og = TestEvent(str: 'okay');

      final encoded = safe.encode(og);
      final decoded = safe.decode(encoded);

      expect(decoded.str, equals(og.str));
    });

    test('wraps event encode Error with direction, kind, and message', () {
      final matcher = isA<EventCodecException>()
          .having(
            (failure) => failure.direction,
            'direction',
            EventCodecDirection.encode,
          )
          .having((failure) => failure.kind, 'kind', 'TestEvent')
          .having(
            (failure) => failure.message,
            'message',
            'Failed to encode event of kind TestEvent',
          )
          .having((failure) => failure.error, 'error', isA<StateError>())
          .having(
            (failure) => failure.toString(),
            'toString',
            contains(
              'EventCodecException{kind: TestEvent, direction: EventCodecDirection.encode, message: Failed to encode event of kind TestEvent, error:',
            ),
          );

      expect(() => safe.encode(TestEvent(str: 'fatal')), throwsA(matcher));
    });

    test('wraps event decode Error', () {
      final encoded = EncodedEvent(
        kind: 'fatal',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(
        () => safe.decode(encoded),
        throwsA(
          isA<EventCodecException>()
              .having(
                (failure) => failure.direction,
                'direction',
                EventCodecDirection.decode,
              )
              .having((failure) => failure.kind, 'kind', 'fatal')
              .having(
                (failure) => failure.message,
                'message',
                'Failed to decode event of kind fatal',
              )
              .having(
                (failure) => failure.error,
                'error',
                isA<ArgumentError>(),
              ),
        ),
      );
    });

    test('wraps codec type Error', () {
      final encoded = EncodedEvent(
        kind: 'test',
        bytes: JsonConverter.encode({'str': 123}), // number instead of string
      );

      expect(
        () => safe.decode(encoded),
        throwsA(
          isA<EventCodecException>().having(
            (failure) => failure.error,
            'error',
            isA<TypeError>(),
          ),
        ),
      );
    });

    test('wraps JsonConverter decode Exception', () {
      final encoded = EncodedEvent(
        kind: 'test',
        bytes: Uint8List.fromList([0xFF]),
      );

      expect(
        () => safe.decode(encoded),
        throwsA(
          isA<EventCodecException>().having(
            (failure) => failure.error,
            'error',
            isA<FormatException>(),
          ),
        ),
      );
    });
  });
}
