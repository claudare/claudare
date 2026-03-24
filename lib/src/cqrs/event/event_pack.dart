import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

import 'encoded_event.dart';

// TODO: streamId should be moved out of here
// as it couples location and event encoding/decoding
// in js it was fine as type system is flexible
// but here just need to provide them separately...
abstract class EventPack<TEvents, TData> {
  StreamIdPattern<TData> get streamIdPattern;

  EncodedEvent encode(TEvents value);
  TEvents decode(EncodedEvent raw);
}
