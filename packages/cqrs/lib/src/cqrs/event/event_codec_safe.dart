import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/exception/event_codec_exception.dart';

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
    } catch (error, stackTrace) {
      if (isJsonExceptionLikeError(error)) {
        throw EventCodecException(
          'Failed to encode event',
          direction: EventCodecDirection.encode,
          error: error,
          stackTrace: stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
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
    } catch (error, stackTrace) {
      if (isJsonExceptionLikeError(error)) {
        throw EventCodecException(
          "Failed to decode event of kind '${value.kind}'",
          direction: EventCodecDirection.decode,
          error: error,
          stackTrace: stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
