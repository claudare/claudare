import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/command/command_executor.dart';
import 'package:core/src/cqrs/cqrs_runtime/bound_command.dart';
import 'package:core/src/cqrs/event_store/event_store.dart';
import 'package:core/src/cqrs/projection/projection_runtime.dart';
import 'package:core/src/cqrs/projection/projection.dart';

/// [CqrsRuntime] is all in one place for local CQRS.
/// This class will process commands and ensure that the projections get new events.
class CqrsRuntime {
  final EventStore _eventStore;
  late final List<ProjectionRuntime> _projectionRunners;
  final DateTime Function() _getTime;
  final String Function() _getId;

  CqrsRuntime({
    required EventStore eventStore,
    required List<Projection> projectors,
    required DateTime Function() getTime,
    required String Function() getId,
  }) : _eventStore = eventStore,
       _getId = getId,
       _getTime = getTime {
    _projectionRunners =
        projectors
            .map((projector) => ProjectionRuntime(_eventStore, projector))
            .toList();
  }

  Future<void> init() async {
    //
  }

  BoundCommand<TInput> bindCommand<TInput>(
    Command<TInput> command,
    List<Projection> consistentProjectors,
  ) {
    final executor = CommandExecutor(_eventStore);

    return BoundCommand(
      executor: executor,
      command: command,
      consistentRunners: [], // TODO
      eventualRunners: [],
    );
  }
}
