import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  group('EventRegistry', () {
    for (final kind in [
      SystemEventKinds.streamDeleted,
      SystemEventKinds.eventErased,
      r'$unknown',
      r'$',
    ]) {
      test('rejects registration of $kind', () {
        expect(
          () => EventRegistry().add(_TestEventCodec(kind)),
          throwsA(isA<EventRegistryException>()),
        );
      });

      test('rejects encoding when a codec changes its kind to $kind', () {
        final codec = _MutableCodec();
        final registry = EventRegistry()..add(codec);
        codec.kind = kind;
        expect(
          () => registry.encode(const _TestEvent('value')),
          throwsA(
            isA<EventCodecException>().having(
              (error) => error.direction,
              'direction',
              EventCodecDirection.encode,
            ),
          ),
        );
      });
    }
    for (final kind in [
      SystemEventKinds.eventErased,
      SystemEventKinds.streamDeleted,
    ]) {
      test('rejects $kind without an application decoder', () {
        expect(
          () => EventRegistry().decodeObject(
            EncodedEvent(kind: kind, bytes: Uint8List(0)),
          ),
          throwsA(
            isA<EventCodecException>().having(
              (error) => error.direction,
              'direction',
              EventCodecDirection.decode,
            ),
          ),
        );
      });
    }
    test('encodes by Dart type and decodes by persisted kind', () {
      final registry = EventRegistry()..add(const _TestEventCodec('test'));

      final encoded = registry.encode(const _TestEvent('value'));
      final decoded = registry.decode<_TestEvent>(encoded);

      expect(encoded.kind, 'test');
      expect(decoded.value, 'value');
    });

    test('rejects an empty persisted kind', () {
      final registry = EventRegistry();

      expect(
        () => registry.add(const _TestEventCodec('  ')),
        throwsA(isA<EventRegistryException>()),
      );
    });

    test('rejects duplicate persisted kinds', () {
      final registry = EventRegistry()..add(const _TestEventCodec('duplicate'));

      expect(
        () => registry.add(const _OtherEventCodec('duplicate')),
        throwsA(isA<EventRegistryException>()),
      );
    });

    test('rejects duplicate Dart event types', () {
      final registry = EventRegistry()..add(const _TestEventCodec('first'));

      expect(
        () => registry.add(const _TestEventCodec('second')),
        throwsA(isA<EventRegistryException>()),
      );
    });

    test('fails explicitly for an unregistered Dart event type', () {
      expect(
        () => EventRegistry().encode(const _TestEvent('value')),
        throwsA(
          isA<EventCodecException>().having(
            (failure) => failure.direction,
            'direction',
            EventCodecDirection.encode,
          ),
        ),
      );
    });

    test('fails explicitly for an unknown kind', () {
      expect(
        () => EventRegistry().decode<Object>(
          EncodedEvent(kind: 'unknown', bytes: Uint8List(0)),
        ),
        throwsA(
          isA<EventCodecException>().having(
            (failure) => failure.direction,
            'direction',
            EventCodecDirection.decode,
          ),
        ),
      );
    });

    test('fails explicitly when the requested event family is wrong', () {
      final registry = EventRegistry()..add(const _TestEventCodec('test'));
      final encoded = registry.encode(const _TestEvent('value'));

      expect(
        () => registry.decode<_OtherEvent>(encoded),
        throwsA(isA<EventCodecException>()),
      );
    });
  });
}

final class _TestEvent {
  final String value;

  const _TestEvent(this.value);
}

final class _MutableCodec implements EventCodec<_TestEvent> {
  @override
  String kind = 'test';

  @override
  Uint8List toBytes(_TestEvent event) => Uint8List(0);

  @override
  _TestEvent fromBytes(Uint8List bytes) => const _TestEvent('');
}

final class _OtherEvent {
  final String value;

  const _OtherEvent(this.value);
}

final class _TestEventCodec implements EventCodec<_TestEvent> {
  @override
  final String kind;

  const _TestEventCodec(this.kind);

  @override
  Uint8List toBytes(_TestEvent event) =>
      Uint8List.fromList(event.value.codeUnits);

  @override
  _TestEvent fromBytes(Uint8List bytes) =>
      _TestEvent(String.fromCharCodes(bytes));
}

final class _OtherEventCodec implements EventCodec<_OtherEvent> {
  @override
  final String kind;

  const _OtherEventCodec(this.kind);

  @override
  Uint8List toBytes(_OtherEvent event) =>
      Uint8List.fromList(event.value.codeUnits);

  @override
  _OtherEvent fromBytes(Uint8List bytes) =>
      _OtherEvent(String.fromCharCodes(bytes));
}
