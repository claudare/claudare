part of 'note.dart';

class NoteTrashed extends NoteEvent {
  static const String kind = 'note.trashed';

  const NoteTrashed();

  @override
  Map<String, dynamic> toJson() {
    return {};
  }

  factory NoteTrashed.fromJson(Map<String, dynamic> json) {
    return NoteTrashed();
  }

  @override
  String toString() {
    return 'NoteTrashed{}';
  }
}

final class NoteTrashedCodec implements EventCodec<NoteTrashed> {
  const NoteTrashedCodec();

  @override
  String get kind => NoteTrashed.kind;

  @override
  Uint8List toBytes(NoteTrashed event) => JsonConverter.encode(event.toJson());

  @override
  NoteTrashed fromBytes(Uint8List bytes) =>
      NoteTrashed.fromJson(JsonConverter.decode(bytes));
}
