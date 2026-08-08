part of 'note.dart';

// TODO: there is no note deletion
// just moving to a different group (like trash)
// deletion is a permanent and irrevokable action
class NoteTrashed extends NoteEvent {
  // how to do "codec migrations"
  static const String oldKind = 'note.deleted';
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
    return 'NoteDeleted{}';
  }
}
