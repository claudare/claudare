part of 'note.dart';

class NoteCreated extends NoteEvent {
  static const String kind = 'note.created'; // ill try with dots

  const NoteCreated();

  @override
  Map<String, dynamic> toJson() {
    return {};
  }

  factory NoteCreated.fromJson(Map<String, dynamic> json) {
    return NoteCreated();
  }

  @override
  String toString() {
    return 'NoteCreated{}';
  }
}
