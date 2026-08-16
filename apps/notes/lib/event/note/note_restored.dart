part of 'note.dart';

// TODO: there is no note deletion
// just moving to a different group (like trash)
// deletion is a permanent and irrevokable action
class NoteRestored extends NoteEvent {
  static const String kind = 'note.restored';

  const NoteRestored();

  @override
  Map<String, dynamic> toJson() {
    return {};
  }

  factory NoteRestored.fromJson(Map<String, dynamic> json) {
    return NoteRestored();
  }

  @override
  String toString() {
    return 'NoteRestored{}';
  }
}

final class NoteRestoredCodec implements EventCodec<NoteRestored> {
  const NoteRestoredCodec();

  @override
  String get kind => NoteRestored.kind;

  @override
  Uint8List toBytes(NoteRestored event) => JsonConverter.encode(event.toJson());

  @override
  NoteRestored fromBytes(Uint8List bytes) =>
      NoteRestored.fromJson(JsonConverter.decode(bytes));
}
