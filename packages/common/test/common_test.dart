import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceId', () {
    test('default constructor validates supported values', () {
      expect(DeviceId(0), const DeviceId.self());
      expect(DeviceId(1).value, 1);
      expect(DeviceId(0xFFFF - 1).value, 0xFFFF - 1);
      expect(() => DeviceId(-1), throwsFormatException);
      expect(() => DeviceId(0xFFFF), throwsFormatException);
    });

    test('round trips JSON and little-endian bytes', () {
      final deviceId = DeviceId(0x1234);

      expect(DeviceId.fromJson(deviceId.toJson()), deviceId);
      expect(deviceId.toBytes(), Uint8List.fromList([0x34, 0x12]));
      expect(DeviceId.fromBytes(deviceId.toBytes()), deviceId);
    });
  });

  group('DeviceIdSequencePair', () {
    test('compares by device and sequence', () {
      expect(
        DeviceIdSequencePair(DeviceId(3), 8),
        DeviceIdSequencePair(DeviceId(3), 8),
      );
      expect(
        DeviceIdSequencePair(DeviceId(3), 8),
        isNot(DeviceIdSequencePair(DeviceId(4), 8)),
      );
    });
  });

  group('CausalSequence', () {
    test('starts at zero and advances from the latest synced sequence', () {
      final sequence = CausalSequence();

      expect(
        sequence.current(),
        const DeviceIdSequencePair(DeviceId.self(), 0),
      );

      sequence.sync(DeviceIdSequencePair(DeviceId(5), 99));

      expect(
        sequence.next(DeviceId(6)),
        DeviceIdSequencePair(DeviceId(6), 100),
      );
      expect(sequence.copy().current(), sequence.current());
    });

    test('ignores an older synced sequence and resets to zero', () {
      final sequence = CausalSequence.fromSequencePair(
        DeviceIdSequencePair(DeviceId(5), 4),
      );

      sequence.sync(DeviceIdSequencePair(DeviceId(6), 3));
      expect(sequence.current(), DeviceIdSequencePair(DeviceId(5), 4));

      sequence.reset();
      expect(
        sequence.current(),
        const DeviceIdSequencePair(DeviceId.self(), 0),
      );
    });
  });

  group('DeviceSequences', () {
    test('tracks and validates each device independently', () {
      final sequences = DeviceSequences();

      expect(sequences.nextSequence(DeviceId(1)), 1);
      expect(sequences.nextSequence(DeviceId(1)), 2);
      expect(sequences.nextSequence(DeviceId(2)), 1);
      expect(sequences.isInOrder(DeviceIdSequencePair(DeviceId(1), 3)), isTrue);
      expect(
        () => sequences.apply(DeviceIdSequencePair(DeviceId(1), 4)),
        throwsStateError,
      );
    });

    test('round trips JSON and resets', () {
      final sequences = DeviceSequences()
        ..apply(DeviceIdSequencePair(DeviceId(1), 1))
        ..apply(DeviceIdSequencePair(DeviceId(2), 1));

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
