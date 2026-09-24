import 'package:flutter/material.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/common.dart';

class NoteListItem extends StatelessWidget {
  final NoteState note;
  final VoidCallback onTap;

  const NoteListItem({super.key, required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(note.title),
      subtitle: Text(
        note.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        children: [
          Text(
            formatDateTime(note.updatedAt),
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (note.isTrashed) const Text('Trashed'),
        ],
      ),
      onTap: onTap,
    );
  }
}
