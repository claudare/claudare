import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceId', () {
    test('validates supported values', () {
      expect(DeviceId.validated(1), const DeviceId(1));
      expect(DeviceId.validated(0xFFFF - 1), const DeviceId.unassigned());
      expect(() => DeviceId.validated(-1), throwsFormatException);
      expect(() => DeviceId.validated(0xFFFF), throwsFormatException);
    });

    test('round trips JSON and little-endian bytes', () {
      const deviceId = DeviceId(0x1234);

      expect(DeviceId.fromJson(deviceId.toJson()), deviceId);
      expect(deviceId.toBytes(), Uint8List.fromList([0x34, 0x12]));
      expect(DeviceId.fromBytes(deviceId.toBytes()), deviceId);
    });
  });

  group('DeviceIdSequencePair', () {
    test('compares by device and sequence', () {
      expect(
        const DeviceIdSequencePair(DeviceId(3), 8),
        const DeviceIdSequencePair(DeviceId(3), 8),
      );
      expect(
        const DeviceIdSequencePair(DeviceId(3), 8),
        isNot(const DeviceIdSequencePair(DeviceId(4), 8)),
      );
    });
  });

  group('CausalSequence', () {
    test('starts at zero and advances from the latest synced sequence', () {
      final sequence = CausalSequence();

      expect(
        sequence.current(),
        const DeviceIdSequencePair(DeviceId.zero(), 0),
      );

      sequence.sync(const DeviceIdSequencePair(DeviceId(5), 99));

      expect(
        sequence.next(const DeviceId(6)),
        const DeviceIdSequencePair(DeviceId(6), 100),
      );
      expect(sequence.copy().current(), sequence.current());
    });

    test('ignores an older synced sequence and resets to zero', () {
      final sequence = CausalSequence.fromSequencePair(
        const DeviceIdSequencePair(DeviceId(5), 4),
      );

      sequence.sync(const DeviceIdSequencePair(DeviceId(6), 3));
      expect(sequence.current(), const DeviceIdSequencePair(DeviceId(5), 4));

      sequence.reset();
      expect(
        sequence.current(),
        const DeviceIdSequencePair(DeviceId.zero(), 0),
      );
    });
  });

  group('DeviceSequences', () {
    test('tracks and validates each device independently', () {
      final sequences = DeviceSequences();

      expect(sequences.nextSequence(const DeviceId(1)), 1);
      expect(sequences.nextSequence(const DeviceId(1)), 2);
      expect(sequences.nextSequence(const DeviceId(2)), 1);
      expect(
        sequences.isInOrder(const DeviceIdSequencePair(DeviceId(1), 3)),
        isTrue,
      );
      expect(
        () => sequences.apply(const DeviceIdSequencePair(DeviceId(1), 4)),
        throwsStateError,
      );
    });

    test('round trips JSON and resets', () {
      final sequences = DeviceSequences()
        ..apply(const DeviceIdSequencePair(DeviceId(1), 1))
        ..apply(const DeviceIdSequencePair(DeviceId(2), 1));

      final restored = DeviceSequences.fromJson(sequences.toJson());
      expect(restored.vector, sequences.vector);

      restored.reset();
      expect(restored.vector, isEmpty);
    });
  });

  test('JsonConverter round trips JSON values as bytes', () {
    final bytes = JsonConverter.encode({
      'name': 'Claudare',
      'values': [1, true, null],
    });

    expect(JsonConverter.decode<Map<String, dynamic>>(bytes), {
      'name': 'Claudare',
      'values': [1, true, null],
    });
  });

  test('identifies JSON-like runtime errors', () {
    expect(isJsonExceptionLikeError(TypeError()), isTrue);
    expect(
      isJsonExceptionLikeError(
        NoSuchMethodError.withInvocation(Object(), Invocation.getter(#value)),
      ),
      isTrue,
    );
    expect(isJsonExceptionLikeError(RangeError('out of range')), isTrue);
    expect(isJsonExceptionLikeError(FormatException('invalid')), isFalse);
    expect(isJsonExceptionLikeError(StateError('invalid')), isFalse);
  });
}
