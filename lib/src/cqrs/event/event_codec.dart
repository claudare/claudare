import 'package:core/src/cqrs/event/encoded_event.dart';

abstract class EventCodec<T> {
  const EventCodec();

  EncodedEvent encode(T event);
  T decode(EncodedEvent encoded);
}
