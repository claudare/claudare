part of 'note.dart';

class NoteContentUpdated extends NoteEvent {
  static const String kind = 'note.content.updated';

  final CrdtTextChange change;

  const NoteContentUpdated({required this.change});

  @override
  Map<String, dynamic> toJson() {
    return {'change': change};
  }

  factory NoteContentUpdated.fromJson(Map<String, dynamic> json) {
    return NoteContentUpdated(change: CrdtTextChange.fromJson(json['change']));
  }

  @override
  String toString() {
    return 'NoteContentUpdated{change: $change}';
  }
}

final class NoteContentUpdatedCodec implements EventCodec<NoteContentUpdated> {
  const NoteContentUpdatedCodec();

  @override
  String get kind => NoteContentUpdated.kind;

  @override
  Uint8List toBytes(NoteContentUpdated event) =>
      JsonConverter.encode(event.toJson());

  @override
  NoteContentUpdated fromBytes(Uint8List bytes) =>
      NoteContentUpdated.fromJson(JsonConverter.decode(bytes));
}
