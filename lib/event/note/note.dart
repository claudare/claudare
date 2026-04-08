part 'note_content_updated.dart';
part 'note_created.dart';
part 'note_restored.dart';
part 'note_title_updated.dart';
part 'note_trashed.dart';

sealed class NoteEvent {
  const NoteEvent();

  Map<String, dynamic> toJson();
}
