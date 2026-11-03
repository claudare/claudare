import 'dart:typed_data';

import 'package:cqrs/src/cqrs/event/system_event_kinds.dart';

/// An encoded event with immutable bytes.
class EncodedEvent {
  final String kind;
  final Uint8List bytes;

  /// Reserved `$` kinds must be known [SystemEventKinds] with empty bytes.
  EncodedEvent({required this.kind, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (kind.startsWith(r'$')) {
      if (((kind != SystemEventKinds.streamDeleted &&
          kind != SystemEventKinds.eventErased))) {
        throw ArgumentError('Invalid framework event kind type: $kind');
      }
      if (bytes.isNotEmpty) {
        throw ArgumentError('Invalid non-empty framework event payload: $kind');
      }
    }
  }
}
