import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/screens/home/note_list_controller.dart';
import 'package:notes/screens/home/widget/note_list.dart';
import 'package:notes/screens/note/note_screen.dart';
import 'package:notes/screens/settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late NoteListController _controller;
  NoteApplication? _application;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final application = NoteApplicationProvider.of(context);
    if (identical(_application, application)) return;

    if (_application != null) {
      _controller.removeListener(_onControllerChanged);
      _controller.dispose();
    }
    _application = application;
    _controller = NoteListController(application);
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.reloadNotes());
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openNote(String? noteId) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => NoteScreen(noteId: noteId)));
    if (mounted) await _controller.reloadNotes();
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => SettingsScreen()));
    if (mounted) await _controller.reloadNotes();
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
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => _openSettings(),
          ),
        ],
      ),
      body:
          _controller.loadError == null
              ? NoteList(noteData: _controller.noteData, openNote: _openNote)
              : Center(
                child: Text('Error loading notes: ${_controller.loadError}'),
              ),
    );
  }
}
