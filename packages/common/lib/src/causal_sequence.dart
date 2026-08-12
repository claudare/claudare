import 'device_id.dart';
import 'device_id_sequence_pair.dart';

/// [CausalSequence] keeps track of the latest causal order based on device ids.
/// It allows to generate next causaly consistent sequence.
/// This is a lamport clock.
class CausalSequence {
  DeviceId _latestDevice;
  int _latestSequence;

  CausalSequence() : _latestDevice = DeviceId.zero(), _latestSequence = 0;

  CausalSequence.fromSequencePair(DeviceIdSequencePair causalSequence)
    : _latestDevice = causalSequence.deviceId,
      _latestSequence = causalSequence.sequence;

  /// when new causal sequence arrives, also used to init
  void sync(DeviceIdSequencePair causalSequence) {
    if (causalSequence.sequence >= _latestSequence) {
      _latestDevice = causalSequence.deviceId;
      _latestSequence = causalSequence.sequence;
    }
  }

  void reset() {
    _latestDevice = DeviceId.zero();
    _latestSequence = 0;
  }

  CausalSequence copy() {
    return CausalSequence.fromSequencePair(current());
  }

  DeviceIdSequencePair current() {
    return DeviceIdSequencePair(_latestDevice, _latestSequence);
  }

  /// when this is ran, the given values must be saved
  /// if any database errors are encountered, the causal order could be
  /// completely messed up
  DeviceIdSequencePair next(DeviceId deviceId) {
    _latestDevice = deviceId;
    _latestSequence += 1;
    return current();
  }

  int nextSequence(DeviceId deviceId) {
    _latestDevice = deviceId;
    _latestSequence += 1;
    return _latestSequence;
  }
}
