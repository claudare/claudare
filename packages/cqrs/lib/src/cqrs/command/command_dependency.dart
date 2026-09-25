import 'package:cqrs/src/cqrs/command/command_id.dart';

/// A compact contiguous causal history indexed by actor.
class CommandDependency {
  final Map<String, int> _values;

  CommandDependency([Map<String, int> values = const {}])
    : _values = Map.unmodifiable(_validated(values));

  static Map<String, int> _validated(Map<String, int> values) {
    for (final entry in values.entries) {
      if (entry.value < 0) {
        throw FormatException(
          'command dependency sequence must be non-negative: ${entry.value}',
        );
      }
    }
    return Map.of(values)..removeWhere((_, value) => value == 0);
  }

  int value(String actor) => _values[actor] ?? 0;

  Map<String, int> get values => _values;

  bool contains(CommandDependency dependency) {
    for (final entry in dependency._values.entries) {
      if (value(entry.key) < entry.value) return false;
    }
    return true;
  }

  CommandDependency advance(CommandId commandId) {
    final expected = value(commandId.actor) + 1;
    if (commandId.sequence != expected) {
      throw StateError(
        'out-of-order command ${commandId.sequence}, expected $expected for ${commandId.actor}',
      );
    }
    return CommandDependency({..._values, commandId.actor: commandId.sequence});
  }

  Map<String, int> toJson() {
    final entries =
        _values.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return {for (final entry in entries) entry.key: entry.value};
  }

  factory CommandDependency.fromJson(Map<String, dynamic> json) {
    return CommandDependency({
      for (final entry in json.entries) entry.key: entry.value as int,
    });
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CommandDependency || _values.length != other._values.length) {
      return false;
    }
    return _values.entries.every(
      (entry) => other.value(entry.key) == entry.value,
    );
  }

  @override
  int get hashCode {
    var result = 0;
    for (final entry in toJson().entries) {
      result = Object.hash(result, entry.key, entry.value);
    }
    return result;
  }

  @override
  String toString() => 'CommandDependency(${toJson()})';
}
