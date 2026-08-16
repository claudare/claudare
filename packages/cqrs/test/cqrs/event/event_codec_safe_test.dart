import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/event/event_codec_safe.dart';
import 'package:test/test.dart';

class TestEvent {
  String str;

  TestEvent({required this.str});
}

class TestCodec implements EventCodec<TestEvent> {
  @override
  String get kind => 'test';

  @override
  Uint8List toBytes(TestEvent event) {
    if (event.str == 'fatal') {
      throw StateError('intentionally fatal error');
    }
    return JsonConverter.encode({'str': event.str});
  }

  @override
  TestEvent fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError('intentionally fatal error');
    }

    final map = JsonConverter.decode(bytes);
    return TestEvent(str: map['str'] as String);
  }
}

void main() {
  group('Event codec safe', () {
    late EventCodecSafe<TestEvent> safe;

    setUp(() {
      safe = EventCodecSafe(TestCodec());
    });

    test('json roundtrip okay', () {
      final original = TestEvent(str: 'okay');

      final encoded = safe.toBytes(original);
      final decoded = safe.fromBytes(encoded);

      expect(decoded.str, equals(original.str));
    });

    test('wraps event encode Error with direction, kind, and message', () {
      final matcher = isA<EventCodecException>()
          .having(
            (failure) => failure.direction,
            'direction',
            EventCodecDirection.encode,
          )
          .having((failure) => failure.kind, 'kind', 'test')
          .having(
            (failure) => failure.message,
            'message',
            'Failed to encode event of kind test',
          )
          .having((failure) => failure.error, 'error', isA<StateError>())
          .having(
            (failure) => failure.toString(),
            'toString',
            contains(
              'EventCodecException{kind: test, direction: EventCodecDirection.encode, message: Failed to encode event of kind test, error:',
            ),
          );

      expect(() => safe.toBytes(TestEvent(str: 'fatal')), throwsA(matcher));
    });

    test('wraps event decode Error', () {
      expect(
        () => safe.fromBytes(Uint8List(0)),
        throwsA(
          isA<EventCodecException>()
              .having(
                (failure) => failure.direction,
                'direction',
                EventCodecDirection.decode,
              )
              .having((failure) => failure.kind, 'kind', 'test')
              .having(
                (failure) => failure.message,
                'message',
                'Failed to decode event of kind test',
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
      expect(
        () => safe.fromBytes(JsonConverter.encode({'str': 123})),
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
      expect(
        () => safe.fromBytes(Uint8List.fromList([0xFF])),
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
