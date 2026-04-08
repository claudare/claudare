import 'package:flutter/material.dart';
import 'package:notes_app_v0/runtime/notes_runtime.dart';
import 'package:notes_app_v0/screens/home/note_list_controller.dart';
import 'package:notes_app_v0/screens/home/widget/note_list.dart';
import 'package:notes_app_v0/screens/note/note_screen.dart';

class HomeScreen extends StatefulWidget {
  final NotesRuntime notesRuntime;

  const HomeScreen({super.key, required this.notesRuntime});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late NoteListController _controller;

  @override
  void initState() {
    super.initState();

    _controller = NoteListController(widget.notesRuntime);
    _controller.addListener(() => setState(() {}));
    _controller.reloadNotes();
  }

  @override
  void dispose() {
    _controller.dispose(); // listener list is cleared on dispose
    super.dispose();
  }

  Future<void> _openNote(String? noteId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) =>
                NoteScreen(noteId: noteId, notesRuntime: widget.notesRuntime),
      ),
    );
    // this will rerun after push is over
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
