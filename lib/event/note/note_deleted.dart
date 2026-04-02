part of 'note.dart';

// TODO: there is no note deletion
// just moving to a different group (like trash)
// deletion is a permanent and irrevokable action
class NoteDeleted extends NoteEvent {
  static const String kind = 'note.deleted';

  const NoteDeleted();

  @override
  Map<String, dynamic> toJson() {
    return {};
  }

  factory NoteDeleted.fromJson(Map<String, dynamic> json) {
    return NoteDeleted();
  }

  @override
  String toString() {
    return 'NoteDeleted{}';
  }
}
