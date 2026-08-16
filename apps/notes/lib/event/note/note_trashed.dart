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
