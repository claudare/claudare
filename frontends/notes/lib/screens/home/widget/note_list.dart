import 'package:flutter/material.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/screens/home/widget/note_list_item.dart';

class NoteList extends StatelessWidget {
  final Future<void> Function(String? noteId) openNote;
  final List<NoteState> noteData;
  final NoteSortOrder order;
  final bool showTrashMarker;

  const NoteList({
    super.key,
    required this.noteData,
    required this.openNote,
    required this.order,
    this.showTrashMarker = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: noteData.length,
      itemBuilder: (context, index) {
        final note = noteData[index];
        return NoteListItem(
          note: note,
          order: order,
          showTrashMarker: showTrashMarker,
          onTap: () {
            openNote(note.noteId);
          },
        );
      },
    );
  }
}
