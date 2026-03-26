// wrap the codec to make it safe
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/exception/event_codec_exception.dart';

class EventCodecSafe<Event> implements EventCodec<Event> {
  final EventCodec<Event> _codec;

  const EventCodecSafe(this._codec);

  @override
  encode(value) {
    try {
      return _codec.encode(value);
    } catch (cause) {
      throw EventCodecException(
        "Failed to encode event",
        direction: EventCodecDirection.encode,
        cause: cause,
      );
    }
  }

  @override
  decode(value) {
    try {
      return _codec.decode(value);
    } catch (cause) {
      throw EventCodecException(
        "Failed to decode event of kind '${value.kind}'",
        direction: EventCodecDirection.decode,
        cause: cause,
      );
    }
  }
}
