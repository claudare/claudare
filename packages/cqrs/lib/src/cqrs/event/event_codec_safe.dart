import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/exception/event_codec_exception.dart';

class EventCodecSafe<Event> implements EventCodec<Event> {
  final EventCodec<Event> _codec;

  const EventCodecSafe(this._codec);

  @override
  encode(value) {
    final kind = value.runtimeType.toString();
    try {
      return _codec.encode(value);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        EventCodecException(
          'Failed to encode event of kind $kind',
          direction: EventCodecDirection.encode,
          kind: kind,
          error: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  @override
  decode(value) {
    try {
      return _codec.decode(value);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        EventCodecException(
          'Failed to decode event of kind ${value.kind}',
          direction: EventCodecDirection.decode,
          kind: value.kind,
          error: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }
}
