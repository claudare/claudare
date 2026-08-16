import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';
import 'package:notes/event/note/note.dart';

const noteCodec = NoteCodec();

class NoteCodec implements EventCodec<NoteEvent> {
  const NoteCodec();

  @override
  EncodedEvent encode(NoteEvent event) {
    final bytes = JsonConverter.encode(event.toJson());

    switch (event) {
      case NoteContentUpdated():
        return EncodedEvent(kind: NoteContentUpdated.kind, bytes: bytes);
      case NoteCreated():
        return EncodedEvent(kind: NoteCreated.kind, bytes: bytes);
      case NoteRestored():
        return EncodedEvent(kind: NoteRestored.kind, bytes: bytes);
      case NoteTitleUpdated():
        return EncodedEvent(kind: NoteTitleUpdated.kind, bytes: bytes);
      case NoteTrashed():
        return EncodedEvent(kind: NoteTrashed.kind, bytes: bytes);
    }
  }

  @override
  NoteEvent decode(EncodedEvent encoded) {
    final detailMap = JsonConverter.decode(encoded.bytes);

    switch (encoded.kind) {
      case NoteContentUpdated.kind:
        return NoteContentUpdated.fromJson(detailMap);
      case NoteCreated.kind:
        return NoteCreated.fromJson(detailMap);
      case NoteRestored.kind:
        return NoteRestored.fromJson(detailMap);
      case NoteTitleUpdated.kind:
        return NoteTitleUpdated.fromJson(detailMap);
      case NoteTrashed.kind:
        return NoteTrashed.fromJson(detailMap);
      default:
        throw UnsupportedError('Unknown kind: ${encoded.kind}');
    }
  }
}
