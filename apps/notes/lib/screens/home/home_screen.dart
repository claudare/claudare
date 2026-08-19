import 'package:flutter/material.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/screens/home/note_list_controller.dart';
import 'package:notes/screens/home/widget/note_list.dart';
import 'package:notes/screens/note/note_screen.dart';
import 'package:notes/screens/settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final NoteApplication application;

  const HomeScreen({super.key, required this.application});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late NoteListController _controller;

  // controller for searching
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _controller = NoteListController(widget.application);
    _controller.addListener(() => setState(() {}));
    _controller.reloadNotes();
    _searchController.addListener(() {
      _onSearchTextChange(_searchController.text);
    });
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
                NoteScreen(noteId: noteId, application: widget.application),
      ),
    );
    // this will rerun after push is over
    await _controller.reloadNotes();
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => SettingsScreen()));
    // this will rerun after push is over
    await _controller.reloadNotes();
  }

  Future<void> _newNote() async {
    await _openNote(null);
  }

  // TODO: debounce me
  void _onSearchTextChange(String text) {
    // search is its own popup?

    _controller.setSearch(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notes'),
        actions: [
          IconButton(icon: Icon(Icons.add), onPressed: () => _newNote()),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => _openSettings(),
          ),
        ],
        // flexibleSpace: FlexibleSpaceBar(
        //   title: TextField(controller: _searchController),
        // ),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search notes...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              controller: _searchController,
            ),
          ),
          Expanded(
            child: NoteList(
              noteData: _controller.noteData,
              openNote: _openNote,
            ),
          ),
        ],
      ),
      // body: NoteList(noteData: _controller.noteData, openNote: _openNote),
    );
  }
}
