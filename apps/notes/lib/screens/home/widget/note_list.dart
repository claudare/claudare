import 'package:flutter/material.dart';
import 'package:notes/model/resolved_note.dart';
import 'package:notes/screens/home/widget/note_list_item.dart';

class NoteList extends StatelessWidget {
  final Future<void> Function(String? noteId) openNote;
  final List<ResolvedNote> noteData;

  const NoteList({super.key, required this.noteData, required this.openNote});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: noteData.length,
      itemBuilder: (context, index) {
        final note = noteData[index];
        return NoteListItem(
          note: note,
          onTap: () {
            openNote(note.noteId);
          },
        );
      },
    );
  }
}
