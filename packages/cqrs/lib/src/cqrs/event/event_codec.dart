import 'package:cqrs/src/cqrs/event/encoded_event.dart';

// encodes and decodes Uint8List bytes of the event
abstract class EventCodec<T> {
  const EventCodec();

  EncodedEvent encode(T event);
  T decode(EncodedEvent encoded);
}
