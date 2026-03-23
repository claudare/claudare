import 'package:core/src/cqrs/stored_event.dart';
import 'package:core/src/cqrs/stream_id.dart';

abstract class EventPack<TEvents, TData> {
  StreamId<TData> get streamId;

  EncodedEvent encode(TEvents value);
  TEvents decode(EncodedEvent raw);
}
