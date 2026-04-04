import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:notes_app_v0/application_provider.dart';
import 'package:notes_app_v0/model/note_data.dart';
import 'package:notes_app_v0/screens/note_screen.dart';
import 'package:notes_app_v0/widget/note_list_item.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<NoteData> _noteData = [];

  // pagination here

  @override
  void initState() {
    super.initState();

    print('HomeScreen initState');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    print('HomeScreen didChangeDependencies');

    _reloadLoadNoteData();
  }

  // reloads the data
  Future<void> _reloadLoadNoteData() async {
    print('reloading note data');

    final app = ApplicationProvider.of(context);

    final data = await app.notesRuntime.noteReadModel.getAllNotes();

    setState(() {
      _noteData = data;
    });

    print('got note data $_noteData');
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _openNote(String? noteId) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => NoteScreen(noteId: noteId)));
    // this will rerun after push is over
    // is there a race condition?
    _reloadLoadNoteData();
  }

  Future<void> _newNote() async {
    await _openNote(null);
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
      body: ListView.builder(
        itemCount: _noteData.length,
        itemBuilder: (context, index) {
          final note = _noteData[index];
          return NoteListItem(
            note: note,
            onTap: () {
              _openNote(note.noteId);
            },
          );
        },
      ),
    );
  }
}
