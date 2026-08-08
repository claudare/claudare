import 'package:flutter/material.dart';
import 'package:notes/common.dart';
import 'package:notes/model/resolved_note.dart';

class NoteListItem extends StatelessWidget {
  final ResolvedNote note;
  final VoidCallback onTap;

  const NoteListItem({super.key, required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // nice UI :()
    String categories = '';

    if (note.isTrashed) {
      categories += ' Trashed';
    }

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
          Text(categories),
        ],
      ),
      onTap: onTap,
    );
  }
}
