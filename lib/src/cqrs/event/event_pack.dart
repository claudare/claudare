import 'encoded_event.dart';
import 'package:core/src/cqrs/stream_id.dart';

// TODO: streamId should be moved out of here
// as it couples location and event encoding/decoding
// in js it was fine as type system is flexible
// but here just need to provide them separately...
abstract class EventPack<TEvents, TData> {
  StreamId<TData> get streamId;

  EncodedEvent encode(TEvents value);
  TEvents decode(EncodedEvent raw);
}
