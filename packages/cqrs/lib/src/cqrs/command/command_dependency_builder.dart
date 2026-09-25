import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/command_dependency.dart';

/// A mutable accumulator for a [CommandDependency].
class CommandDependencyBuilder {
  final Map<String, int> _values = {};

  CommandDependencyBuilder();

  /// Applies [commandId] when it advances the recorded sequence for its actor.
  void apply(CommandId commandId) {
    if ((_values[commandId.actor] ?? 0) >= commandId.sequence) return;
    _values[commandId.actor] = commandId.sequence;
  }

  /// Returns an immutable snapshot of the accumulated dependencies.
  CommandDependency finish() => CommandDependency(_values);
}
