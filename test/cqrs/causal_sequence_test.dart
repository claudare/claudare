import 'package:core/src/cqrs/causal_sequence.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/device_id_sequence_pair.dart';
import 'package:test/test.dart';

void main() {
  group('CausalSequence', () {
    // simple all in one test
    test('smoke', () {
      final seq = CausalSequence();

      expect(seq.current(), equals(DeviceIdSequencePair(DeviceId(0), 0)));

      seq.sync(DeviceIdSequencePair(DeviceId(5), 99));

      expect(seq.current(), equals(DeviceIdSequencePair(DeviceId(5), 99)));

      final next = seq.nextSequence(DeviceId(6));

      expect(next, equals(100));
      expect(seq.current(), equals(DeviceIdSequencePair(DeviceId(6), 100)));
    });
  });
}
