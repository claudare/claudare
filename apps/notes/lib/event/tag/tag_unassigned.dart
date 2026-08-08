part of 'tag.dart';

class TagUnassigned extends TagEvent {
  static const String type = 'tag.unassigned';

  final String noteId;

  const TagUnassigned({required this.noteId});

  @override
  Map<String, dynamic> toJson() {
    return {'noteId': noteId};
  }

  factory TagUnassigned.fromJson(Map<String, dynamic> json) {
    return TagUnassigned(noteId: json['noteId'] as String);
  }

  @override
  String toString() {
    return 'TagUnassigned{noteId: $noteId}';
  }
}
