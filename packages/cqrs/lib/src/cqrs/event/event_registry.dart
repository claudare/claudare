import 'dart:typed_data';

import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/event/event_codec_safe.dart';
import 'package:cqrs/src/cqrs/exception/event_codec_exception.dart';

final class EventRegistry {
  final Map<String, _RegisteredEventCodec> _byKind = {};
  final Map<Type, _RegisteredEventCodec> _byType = {};

  void register<T extends Object>(EventCodec<T> codec) {
    final kind = codec.kind;
    if (kind.trim().isEmpty) {
      throw EventRegistryException('Event codec kind must not be empty');
    }
    if (_byKind.containsKey(kind)) {
      throw EventRegistryException(
        'An event codec is already registered for kind $kind',
      );
    }
    if (_byType.containsKey(T)) {
      throw EventRegistryException(
        'An event codec is already registered for Dart type $T',
      );
    }

    final registered = _TypedEventCodec<T>(EventCodecSafe(codec));
    _byKind[kind] = registered;
    _byType[T] = registered;
  }

  EncodedEvent encode(Object event) {
    final registered = _byType[event.runtimeType];
    if (registered == null) {
      throw EventCodecException(
        'No event codec is registered for Dart type ${event.runtimeType}',
        direction: EventCodecDirection.encode,
        kind: '<unregistered>',
      );
    }

    return EncodedEvent(
      kind: registered.kind,
      bytes: registered.toBytes(event),
    );
  }

  T decode<T extends Object>(EncodedEvent encoded) {
    final event = decodeObject(encoded);
    if (event is! T) {
      throw EventCodecException(
        'Event kind ${encoded.kind} decoded to ${event.runtimeType}, '
        'but $T was expected',
        direction: EventCodecDirection.decode,
        kind: encoded.kind,
      );
    }
    return event;
  }

  Object decodeObject(EncodedEvent encoded) {
    final registered = _byKind[encoded.kind];
    if (registered == null) {
      throw EventCodecException(
        'No event codec is registered for kind ${encoded.kind}',
        direction: EventCodecDirection.decode,
        kind: encoded.kind,
      );
    }

    return registered.fromBytes(encoded);
  }
}

// TODO: move to the exception folder?
final class EventRegistryException implements Exception {
  final String message;

  const EventRegistryException(this.message);

  @override
  String toString() => 'EventRegistryException: $message';
}

abstract interface class _RegisteredEventCodec {
  String get kind;
  Uint8List toBytes(Object event);
  Object fromBytes(EncodedEvent encoded);
}

final class _TypedEventCodec<T extends Object>
    implements _RegisteredEventCodec {
  final EventCodecSafe<T> _codec;

  const _TypedEventCodec(this._codec);

  @override
  String get kind => _codec.kind;

  @override
  Uint8List toBytes(Object event) {
    if (event is! T) {
      throw EventCodecException(
        'Event encoder for kind $kind cannot encode ${event.runtimeType}',
        direction: EventCodecDirection.encode,
        kind: kind,
      );
    }
    return _codec.toBytes(event);
  }

  @override
  Object fromBytes(EncodedEvent encoded) => _codec.fromBytes(encoded.bytes);
}
