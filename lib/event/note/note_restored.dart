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
