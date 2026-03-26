import 'package:core/src/cqrs/event/encoded_event.dart';

abstract class EventCodec<T> {
  const EventCodec();

  EncodedEvent encode(T value);
  T decode(EncodedEvent raw);
}
