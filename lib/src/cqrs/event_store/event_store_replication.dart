import 'package:core/src/cqrs/command/command_result.dart';
import 'package:core/src/cqrs/command/encoded_command.dart';
import 'package:core/src/cqrs/device_sequences.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/device_id.dart';

class ReplicatedCommand {
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final CommandResult result;

  const ReplicatedCommand({
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
    required this.result,
  });
}

class ReplicatedEvent {
  final String streamId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  // the device sequence has to be respected in its sequential order
  final int deviceSequence;
  // The events in this change are applied in the order they were emitted
  // the causal sequence seems useless
  final int causalSequence;

  const ReplicatedEvent({
    required this.streamId,
    required this.encodedEvent,
    required this.occuredAt,
    required this.deviceSequence,
    required this.causalSequence,
  });
}

// [ReplicatedChange] represents a sync boundary
// Either all events are applied (if sequence and dependencies match)
// Or the change gets buffered. Ideally, the order of changes should be
// in causal sequence order?
class ReplicatedChange {
  // If in some rare case there the causal sequence yields a tie, lower device
  // id will win application proirity. Or could drill down to event causal sequences?
  // This needs some research to guarantee order consistency.
  final DeviceId deviceId;
  // applied replicated changes must be incremental for each device
  final int deviceSequence;
  // the causal sequence of the command is the guide on which command should run
  // if it happens that multiple sequences are available.
  // I am still not sure about causality giarantees of this.
  final int causalSequence; // not needed?

  final ReplicatedCommand command;
  // dependencies must be satisfied for the change to be applied
  final EventDependency dependencies;
  final List<ReplicatedEvent> events;

  const ReplicatedChange({
    required this.deviceId,
    required this.deviceSequence,
    required this.causalSequence,
    required this.command,
    required this.dependencies,
    required this.events,
  });

  bool canApply(
    DeviceSequences commandDeviceSequences,
    EventDependency latestDependencies,
    DeviceId targetDeviceId, // aka thisDeviceId
  ) {
    return false;
  }
}

abstract interface class EventStoreReplication {}
