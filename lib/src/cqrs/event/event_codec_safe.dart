// wrap the codec to make it safe
import 'dart:convert' show JsonUnsupportedObjectError;

import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/exception/event_codec_exception.dart';

class EventCodecSafe<Event> implements EventCodec<Event> {
  final EventCodec<Event> _codec;

  const EventCodecSafe(this._codec);

  @override
  encode(value) {
    try {
      return _codec.encode(value);
    } on JsonUnsupportedObjectError catch (e, st) {
      throw EventCodecException(
        'Failed to encode event: unsupported JSON object (possibly cyclic reference)',
        direction: EventCodecDirection.encode,
        error: e,
        stackTrace: st,
      );
    } on FormatException catch (e, st) {
      throw EventCodecException(
        'Failed to encode event: invalid format',
        direction: EventCodecDirection.encode,
        error: e,
        stackTrace: st,
      );
    } on Exception catch (e, st) {
      throw EventCodecException(
        'Failed to encode event',
        direction: EventCodecDirection.encode,
        error: e,
        stackTrace: st,
      );
    } catch (e, st) {
      Error.throwWithStackTrace(e, st);
    }
  }

  @override
  decode(value) {
    try {
      return _codec.decode(value);
    } on FormatException catch (e, st) {
      throw EventCodecException(
        "Failed to decode event of kind '${value.kind}': invalid JSON format",
        direction: EventCodecDirection.decode,
        error: e,
        stackTrace: st,
      );
    } on JsonUnsupportedObjectError catch (e, st) {
      throw EventCodecException(
        "Failed to decode event of kind '${value.kind}': unsupported JSON object",
        direction: EventCodecDirection.decode,
        error: e,
        stackTrace: st,
      );
    } on Exception catch (e, st) {
      throw EventCodecException(
        "Failed to decode event of kind '${value.kind}'",
        direction: EventCodecDirection.decode,
        error: e,
        stackTrace: st,
      );
    } catch (e, st) {
      Error.throwWithStackTrace(e, st);
    }
  }
}
