import 'package:core/src/counter.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/timestamp.dart';

class GenericIdGenerator {
  final DeviceId _deviceId;
  final Counter16Generator _counterGen;

  const GenericIdGenerator(this._deviceId, this._counterGen);

  GenericIdGenerator.seeded(this._deviceId, {int? counter})
    : _counterGen = Counter16Generator.seeded(counter);

  GenericId next(String scope, Timestamp timestamp) {
    final counterVal = _counterGen.next();

    return GenericId(scope, timestamp, counterVal, _deviceId);
  }
}

/// [GenericId] is the most common form of an id. Whenever an id for whatever
/// internal logic is needed, this implementation is used
/// it has advantage of always carying the timestamp
/// Stringified it is 4 + 1 + 11 + 1 + 3 + 1 + 3 long... 24 chars
/// The scope is limited to 4 characters, but can be empty too
class GenericId {
  static const _strLengthScope = 4;

  final String scope; // is scope really needed?
  final Timestamp timestamp;
  final Counter16 counter;
  final DeviceId deviceId;

  GenericId(this.scope, this.timestamp, this.counter, this.deviceId)
    : assert(scope.length <= _strLengthScope);

  factory GenericId.fromString(String str) {
    final parts = str.split('-');
    if (parts.length != 4) {
      throw FormatException('Invalid GenericId format', str);
    }
    final scope = parts[0];
    if (scope.length > _strLengthScope) {
      throw FormatException('Invalid GenericId scope length', str);
    }
    final timestamp = Timestamp.fromString(parts[1]);
    final counter = Counter16.fromString(parts[2]);
    final deviceId = DeviceId.fromString(parts[3]);

    return GenericId(scope, timestamp, counter, deviceId);
  }

  @override
  String toString() => '$scope-$timestamp-$counter-$deviceId';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GenericId) return false;
    return scope == other.scope &&
        timestamp == other.timestamp &&
        counter == other.counter &&
        deviceId == other.deviceId;
  }

  @override
  int get hashCode =>
      scope.hashCode ^
      timestamp.hashCode ^
      counter.hashCode ^
      deviceId.hashCode;
}
