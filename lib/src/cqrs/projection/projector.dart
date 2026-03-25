import 'package:core/src/cqrs.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';
import 'package:core/src/cqrs/metadata/metadata.dart';

abstract class Projector<Event, StreamIdData> {
  String get name;
  StreamIdPattern<StreamIdData> get streamIdPattern;
  EventCodec<Event> get eventPack;

  Future<void> reset();

  /// return zero version if there is none
  Future<int> getSequenceNumber();

  /// do the application. Throwing is an error
  Future<void> apply({
    required int version,
    required StreamIdData idData,
    required Event event,
    AnyMetadata? metadata,
  });
}
