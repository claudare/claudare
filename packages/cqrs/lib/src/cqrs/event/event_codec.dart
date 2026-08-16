import 'dart:typed_data';

abstract interface class EventCodec<T extends Object> {
  const EventCodec();

  String get kind;

  Uint8List toBytes(T event);
  T fromBytes(Uint8List bytes);
}
