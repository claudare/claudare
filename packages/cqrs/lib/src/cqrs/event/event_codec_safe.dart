import 'dart:typed_data';

import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/exception/event_codec_exception.dart';

class EventCodecSafe<Event extends Object> implements EventCodec<Event> {
  final EventCodec<Event> _codec;

  const EventCodecSafe(this._codec);

  @override
  String get kind => _codec.kind;

  @override
  Uint8List toBytes(Event event) {
    try {
      return _codec.toBytes(event);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        EventCodecException(
          'Failed to encode event of kind ${_codec.kind}',
          direction: EventCodecDirection.encode,
          kind: _codec.kind,
          error: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  @override
  Event fromBytes(Uint8List bytes) {
    try {
      return _codec.fromBytes(bytes);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        EventCodecException(
          'Failed to decode event of kind ${_codec.kind}',
          direction: EventCodecDirection.decode,
          kind: _codec.kind,
          error: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }
}
