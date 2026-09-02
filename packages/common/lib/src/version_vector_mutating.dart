import 'dot.dart';
import 'version_vector.dart';

/// A mutable accumulator for a [VersionVector].
class VersionVectorMutating {
  final Map<int, int> _values = {};

  VersionVectorMutating();

  /// Applies [dot] when it advances the recorded sequence for its device.
  void apply(Dot dot) {
    if ((_values[dot.deviceId] ?? 0) >= dot.sequence) return;
    _values[dot.deviceId] = dot.sequence;
  }

  /// Returns an immutable snapshot of the current version vector.
  VersionVector toVersionVector() => VersionVector(_values);
}
