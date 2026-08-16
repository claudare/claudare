part of 'tag.dart';

class TagAssigned extends TagEvent {
  static const String type = 'tag.assigned';

  final String noteId;

  const TagAssigned({required this.noteId});

  @override
  Map<String, dynamic> toJson() {
    return {'noteId': noteId};
  }

  factory TagAssigned.fromJson(Map<String, dynamic> json) {
    return TagAssigned(noteId: json['noteId'] as String);
  }

  @override
  String toString() {
    return 'TagAssigned{noteId: $noteId}';
  }
}

final class TagAssignedCodec implements EventCodec<TagAssigned> {
  const TagAssignedCodec();

  @override
  String get kind => TagAssigned.type;

  @override
  Uint8List toBytes(TagAssigned event) => JsonConverter.encode(event.toJson());

  @override
  TagAssigned fromBytes(Uint8List bytes) =>
      TagAssigned.fromJson(JsonConverter.decode(bytes));
}
