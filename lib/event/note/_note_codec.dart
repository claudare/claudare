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
      case NoteCreated():
        return EncodedEvent(kind: NoteCreated.kind, detail: detail);
      case NoteTitleUpdated():
        return EncodedEvent(kind: NoteTitleUpdated.kind, detail: detail);
      case NoteContentUpdated():
        return EncodedEvent(kind: NoteContentUpdated.kind, detail: detail);
      case NoteDeleted():
        return EncodedEvent(kind: NoteDeleted.kind, detail: detail);
    }
  }

  @override
  NoteEvent decode(EncodedEvent encoded) {
    final detail = jsonDecode(encoded.detail);

    switch (encoded.kind) {
      case NoteCreated.kind:
        return NoteCreated.fromJson(detail);
      case NoteTitleUpdated.kind:
        return NoteTitleUpdated.fromJson(detail);
      case NoteContentUpdated.kind:
        return NoteContentUpdated.fromJson(detail);
      case NoteDeleted.kind:
        return NoteDeleted.fromJson(detail);
      default:
        throw UnsupportedError('Unknown kind: ${encoded.kind}');
    }
  }
}
