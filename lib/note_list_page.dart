import 'package:flutter/material.dart';
import 'package:notes_app_v0/common.dart';
import 'package:notes_app_v0/note_page.dart';
import 'package:notes_app_v0/repo.dart';

class NoteListPage extends StatefulWidget {
  const NoteListPage({super.key});

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  late final Repo _repo;
  // TODO: show a splashscreen while loading...
  bool loaded = false;

  _NoteListPageState() {
    // example notes notes are loaded here
    _repo = Repo.empty();
  }

  @override
  void initState() {
    super.initState();

    _repo.load().then((_) {
      setState(() {
        loaded = true;
      });
    });
  }

  void _openNote(NoteData note) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NotePage(repo: _repo, note: note),
      ),
    );
  }

  Future<void> _newNote() async {
    final id = Id.random();
    _repo.processEvent(NoteCreated(id), DateTime.now());
    // this is racy
    final note = await _repo.getNote(id);
    if (note == null) {
      throw Exception('new note could not be loaded??');
    }

    _openNote(note);
  }

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notes'),
        actions: [
          IconButton(icon: Icon(Icons.add), onPressed: () => _newNote()),
        ],
      ),
      body: StreamBuilder<void>(
        stream: _repo.order.changes,
        builder: (context, snapshot) {
          return ListView.builder(
            itemCount: _repo.order.items.length,
            itemBuilder: (context, index) {
              final id = _repo.order.items[index];
              return FutureBuilder(
                future: _repo.getNote(id),
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
                          formatDateTime(note.updatedAt),
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        onTap: () => _openNote(note),
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
