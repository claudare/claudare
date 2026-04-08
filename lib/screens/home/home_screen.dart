import 'package:flutter/material.dart';
import 'package:notes_app_v0/application/application_provider.dart';
import 'package:notes_app_v0/screens/home/note_list_controller.dart';
import 'package:notes_app_v0/screens/home/widget/note_list.dart';
import 'package:notes_app_v0/screens/note_screen.dart';

import 'widget/note_list_item.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late NoteListController _controller;

  // pagination here

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    print('HomeScreen didChangeDependencies');

    // but this works!
    final app = ApplicationProvider.of(context);
    _controller = NoteListController(app.notesRuntime);
    _controller.addListener(() => setState(() {}));
    _controller.reloadNotes();
  }

  @override
  void dispose() {
    _controller.dispose(); // listener list is cleared
    super.dispose();
  }

  Future<void> _openNote(String? noteId) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => NoteScreen(noteId: noteId)));
    // this will rerun after push is over
    // is there a race condition?
    await _controller.reloadNotes();
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
      body: NoteList(noteData: _controller.noteData, openNote: _openNote),
    );
  }
}
