import 'package:core/src/cqrs/event/event_pack.dart';

class LiveEventMin {
  final String streamIdStr;
  final dynamic streamIdData;

  /// momento is not needed here. event is already something in memory decoded.
  /// anothe reason to move it out
  final EventPack eventPack;
  final dynamic event;
  final dynamic metadata;
  final DateTime createdAt;

  const LiveEventMin({
    required this.streamIdStr,
    required this.streamIdData,
    required this.eventPack,
    required this.event,
    required this.metadata,
    required this.createdAt,
  });
}

class LiveEventFull extends LiveEventMin {
  final int localSequence;

  /// TODO: version is not required? It is only used on the database level to
  /// prevent Concurrency issues (which there would be extremely few for now)
  final int version;

  const LiveEventFull({
    required super.streamIdStr,
    required super.streamIdData,
    required super.eventPack,
    required super.event,
    required super.metadata,
    required super.createdAt,
    required this.localSequence,
    required this.version,
  });
}
