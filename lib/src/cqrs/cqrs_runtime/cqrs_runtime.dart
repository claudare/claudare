import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/command/command_executor.dart';
import 'package:core/src/cqrs/command/command_side_effects.dart';
import 'package:core/src/cqrs/cqrs_runtime/bound_command.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/event_store/event_store.dart';
import 'package:core/src/cqrs/event_store/event_store_safe.dart';
import 'package:core/src/cqrs/projection/projection_runtime.dart';
import 'package:core/src/cqrs/projection/projection.dart';

/// [CqrsRuntime] is all in one place for local CQRS.
/// This class will process commands and ensure that the projections get new events.
class CqrsRuntime {
  late final EventStoreSafe _eventStore;
  late final List<ProjectionRuntime> _projectionRunners;
  final CommandSideEffects _sideEffects;
  final DeviceId deviceId; // should this be public?

  CqrsRuntime({
    required EventStore eventStore,
    required List<Projection> projectors,
    required CommandSideEffects sideEffects,
    required this.deviceId,
  }) : _sideEffects = sideEffects {
    _eventStore = EventStoreSafe(eventStore);

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
    final executor = CommandExecutor(
      eventStore: _eventStore,
      sideEffects: _sideEffects,
      thisDeviceId: deviceId,
    );

    return BoundCommand(
      executor: executor,
      command: command,
      consistentRunners: [], // TODO
      eventualRunners: [],
    );
  }
}
