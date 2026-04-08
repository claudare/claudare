import 'package:flutter/material.dart';
import 'package:notes_app_v0/common.dart';
import 'package:notes_app_v0/model/note_data.dart';

class NoteListItem extends StatelessWidget {
  final NoteData note;
  final VoidCallback onTap;

  const NoteListItem({super.key, required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(note.title.value),
      subtitle: Text(
        note.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        formatDateTime(note.updatedAt),
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
      onTap: onTap,
    );
  }
}
