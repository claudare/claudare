import 'dart:convert';

import 'package:core/cqrs.dart';
import 'package:notes_app_v0/event/note/note.dart';

const noteCodec = NoteCodec();

class NoteCodec implements EventCodec<NoteEvent> {
  const NoteCodec();

  @override
  EncodedEvent encode(NoteEvent event) {
    final detail = jsonEncode(event.toJson());

    switch (event) {
      case NoteContentUpdated():
        return EncodedEvent(kind: NoteContentUpdated.kind, detail: detail);
      case NoteCreated():
        return EncodedEvent(kind: NoteCreated.kind, detail: detail);
      case NoteRestored():
        return EncodedEvent(kind: NoteRestored.kind, detail: detail);
      case NoteTitleUpdated():
        return EncodedEvent(kind: NoteTitleUpdated.kind, detail: detail);
      case NoteTrashed():
        return EncodedEvent(kind: NoteTrashed.kind, detail: detail);
    }
  }

  @override
  NoteEvent decode(EncodedEvent encoded) {
    final detail = jsonDecode(encoded.detail);

    switch (encoded.kind) {
      case NoteContentUpdated.kind:
        return NoteContentUpdated.fromJson(detail);
      case NoteCreated.kind:
        return NoteCreated.fromJson(detail);
      case NoteRestored.kind:
        return NoteRestored.fromJson(detail);
      case NoteTitleUpdated.kind:
        return NoteTitleUpdated.fromJson(detail);
      case NoteTrashed.oldKind: // migration!
      case NoteTrashed.kind:
        return NoteTrashed.fromJson(detail);
      default:
        throw UnsupportedError('Unknown kind: ${encoded.kind}');
    }
  }
}
