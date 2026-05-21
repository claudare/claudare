import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/utils/converter/json_converter.dart';

/// Please use [JsonConverter] to do the encodings as that will
/// catch any encoding errors and wrap them in [EncodeException] or [DecodeException]
abstract class EventCodec<T> {
  const EventCodec();

  EncodedEvent encode(T event);
  T decode(EncodedEvent encoded);
}
