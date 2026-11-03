import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  test('accepts valid event kinds and payloads', () {
    for (final (kind, payload) in [
      ('test', <int>[]),
      ('test', [1]),
      (SystemEventKinds.streamDeleted, <int>[]),
      (SystemEventKinds.eventErased, <int>[]),
    ]) {
      final event = EncodedEvent(
        kind: kind,
        bytes: Uint8List.fromList(payload),
      );
      expect(event.kind, kind);
      expect(event.bytes, payload);
    }
  });

  test('rejects invalid event kinds and payloads', () {
    for (final (kind, payload) in [
      (SystemEventKinds.streamDeleted, [1]),
      (SystemEventKinds.eventErased, [1]),
      (r'$unknown', <int>[]),
      (r'$unknown', [1]),
      (r'$', <int>[]),
      (r'$', [1]),
    ]) {
      expect(
        () => EncodedEvent(kind: kind, bytes: Uint8List.fromList(payload)),
        throwsArgumentError,
      );
    }
  });

  test('copies supplied payload bytes', () {
    final bytes = Uint8List.fromList([1]);
    final event = EncodedEvent(kind: 'test', bytes: bytes);
    bytes[0] = 2;
    expect(event.bytes, [1]);
  });

  test('exposes immutable payload bytes', () {
    final event = EncodedEvent(kind: 'test', bytes: Uint8List.fromList([1]));
    expect(() => event.bytes[0] = 2, throwsUnsupportedError);
  });
}
