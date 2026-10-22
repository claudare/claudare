import 'package:flutter/material.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/screens/home/widget/note_list_item.dart';

class NoteList extends StatelessWidget {
  final Future<void> Function(String? noteId) openNote;
  final List<NoteState> noteData;
  final NoteSortOrder order;

  const NoteList({
    super.key,
    required this.noteData,
    required this.openNote,
    required this.order,
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
          onTap: () {
            openNote(note.noteId);
          },
        );
      },
    );
  }
}
