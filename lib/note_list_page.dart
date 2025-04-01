import 'package:flutter/material.dart';
import 'package:notes_app_v0/common.dart';
import 'package:notes_app_v0/events.dart';
import 'package:notes_app_v0/note_page.dart';
import 'package:notes_app_v0/repo.dart';
import 'package:notes_app_v0/service_provider.dart';

// does this really need to be Stateful?
class NoteListPage extends StatelessWidget {
  const NoteListPage({super.key});

  void _openNote(BuildContext context, NoteData note) async {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => NotePage(note: note)));
  }

  Future<void> _newNote(BuildContext context) async {
    final repo = ServiceProvider.of(context).repo;
    final noteId = repo.newGenericId('note');
    repo.processEvent(repo.newEventId(), NoteCreated(noteId));
    // this is racy
    final note = await repo.getNote(noteId);
    if (note == null) {
      throw Exception('new note could not be loaded??');
    }

    if (context.mounted) {
      _openNote(context, note);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ServiceProvider.of(context).repo;

    return Scaffold(
      appBar: AppBar(
        title: Text('Notes'),
        actions: [
          IconButton(icon: Icon(Icons.add), onPressed: () => _newNote(context)),
        ],
      ),
      body: StreamBuilder<void>(
        stream: repo.order.changes,
        builder: (context, snapshot) {
          return ListView.builder(
            itemCount: repo.order.items.length,
            itemBuilder: (context, index) {
              final id = repo.order.items[index];
              return FutureBuilder(
                future: repo.getNote(id),
                builder: (context, snapshot) {
                  final note = snapshot.data;

                  if (note == null) {
                    return SizedBox.shrink();
                  }

                  return StreamBuilder<void>(
                    stream: note.changes,
                    builder: (context, snapshot) {
                      return ListTile(
                        title: Text(
                          note.title.isEmpty ? 'No title' : note.title,
                        ),
                        subtitle: Text(
                          note.content.isEmpty
                              ? 'No content'
                              : note.getPreviewContent(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          formatDateTime(note.updatedAt.toDateTime()),
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        onTap: () => _openNote(context, note),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
