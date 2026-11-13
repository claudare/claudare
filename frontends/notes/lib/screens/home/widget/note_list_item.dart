import 'package:flutter/material.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/common.dart';

class NoteListItem extends StatelessWidget {
  final NoteModel note;
  final NoteSortOrder order;
  final VoidCallback onTap;
  final bool showTrashMarker;

  const NoteListItem({
    super.key,
    required this.note,
    required this.onTap,
    required this.order,
    this.showTrashMarker = false,
  });

  @override
  Widget build(BuildContext context) {
    final showCreated =
        order == NoteSortOrder.createdAtAscending ||
        order == NoteSortOrder.createdAtDescending;
    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(note.title)),
          if (showTrashMarker && note.isTrashed)
            Text('In Trash', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      subtitle: Text(
        note.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${showCreated ? 'Created' : 'Edited'}\n'
        '${formatDateTime(showCreated ? note.createdAt : note.updatedAt)}',
        textAlign: TextAlign.end,
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
      onTap: onTap,
    );
  }
}
