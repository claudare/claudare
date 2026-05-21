import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/exception/event_codec_exception.dart';

class EventCodecSafe<Event> implements EventCodec<Event> {
  final EventCodec<Event> _codec;

  const EventCodecSafe(this._codec);

  @override
  encode(value) {
    try {
      return _codec.encode(value);
    } on Exception catch (e, st) {
      throw EventCodecException(
        'Failed to encode event',
        direction: EventCodecDirection.encode,
        error: e,
        stackTrace: st,
      );
    } catch (e, st) {
      if (_isExceptionLikeError(e)) {
        throw EventCodecException(
          "Failed to encode event (exception-like error)",
          direction: EventCodecDirection.encode,
          error: e,
          stackTrace: st,
        );
      }

      Error.throwWithStackTrace(e, st);
    }
  }

  @override
  decode(value) {
    try {
      return _codec.decode(value);
    } on Exception catch (e, st) {
      throw EventCodecException(
        "Failed to decode event of kind '${value.kind}'",
        direction: EventCodecDirection.decode,
        error: e,
        stackTrace: st,
      );
    } catch (e, st) {
      if (_isExceptionLikeError(e)) {
        throw EventCodecException(
          "Failed to decode event of kind '${value.kind}' (exception-like error)",
          direction: EventCodecDirection.decode,
          error: e,
          stackTrace: st,
        );
      }
      Error.throwWithStackTrace(e, st);
    }
  }
}

// these errors can happen when json is cast to objects
// the application should not crash!
bool _isExceptionLikeError(Object error) {
  return error is TypeError ||
      error is NoSuchMethodError ||
      error is RangeError;
}
