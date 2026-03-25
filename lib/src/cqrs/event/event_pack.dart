import 'encoded_event.dart';

abstract class EventPack<TEvents> {
  EncodedEvent encode(TEvents value);
  TEvents decode(EncodedEvent raw);
}
