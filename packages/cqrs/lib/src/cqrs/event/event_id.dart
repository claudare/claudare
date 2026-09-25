import 'package:cqrs/src/cqrs/command/command_id.dart';

class EventId extends CommandId {
  final int index;

  EventId(super.actor, super.sequence, this.index) {
    if (index < 0) {
      throw FormatException('event index must be non-negative: $index');
    }
  }

  CommandId get commandId => CommandId(actor, sequence);

  @override
  List<dynamic> toJson() => [actor, sequence, index];

  factory EventId.fromJson(List<dynamic> json) {
    if (json.length != 3) {
      throw const FormatException(
        'event id must contain actor, sequence, and index',
      );
    }
    return EventId(json[0] as String, json[1] as int, json[2] as int);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is EventId &&
          actor == other.actor &&
          sequence == other.sequence &&
          index == other.index;

  @override
  int get hashCode => Object.hash(actor, sequence, index);

  @override
  String toString() => 'EventId($actor,$sequence,$index)';
}
