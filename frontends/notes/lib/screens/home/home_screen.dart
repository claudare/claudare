import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/layout_breakpoints.dart';
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late NoteListController _controller;
  NotesApp? _application;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final application = NotesAppProvider.of(context);
    if (identical(_application, application)) {
      return;
    }

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
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => SettingsScreen()));
    if (mounted) await _controller.reloadNotes();
  }

  Future<void> _newNote() async {
    await _openNote(null);
  }

  String _sortLabel(NoteSortOrder order) => switch (order) {
    NoteSortOrder.updatedAtDescending => 'Last edited, newest first',
    NoteSortOrder.updatedAtAscending => 'Last edited, oldest first',
    NoteSortOrder.createdAtDescending => 'Created, newest first',
    NoteSortOrder.createdAtAscending => 'Created, oldest first',
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= LayoutBreakpoints.wide;
        final drawerOpen = _scaffoldKey.currentState?.isDrawerOpen ?? false;
        if (wide && drawerOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scaffoldKey.currentState?.closeDrawer();
          });
        }
        return Row(
          children: [
            SizedBox(
              width: wide ? 280 : 0,
              child: wide
                  ? Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: _buildMenu(closeDrawer: false),
                    )
                  : null,
            ),
            Expanded(child: _buildContent(wide, drawerOpen)),
          ],
        );
      },
    );
  }

  Widget _buildContent(bool wide, bool drawerOpen) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        automaticallyImplyLeading: !wide,
        title: Text(
          _controller.category == NoteCategory.active ? 'Notes' : 'Trash',
        ),
        actions: [
          PopupMenuButton<NoteSortOrder>(
            tooltip: 'Sort notes',
            icon: const Icon(Icons.sort),
            enabled: !_controller.isLoading,
            onSelected: _controller.setOrder,
            itemBuilder: (context) => [
              for (final order in [
                NoteSortOrder.updatedAtDescending,
                NoteSortOrder.updatedAtAscending,
                NoteSortOrder.createdAtDescending,
                NoteSortOrder.createdAtAscending,
              ])
                CheckedPopupMenuItem(
                  value: order,
                  checked: order == _controller.order,
                  child: Text(_sortLabel(order)),
                ),
            ],
          ),
          if (_controller.category == NoteCategory.active)
            IconButton(
              tooltip: 'New note',
              icon: Icon(Icons.add),
              onPressed: () => _newNote(),
            ),
        ],
      ),
      drawerEnableOpenDragGesture: !wide,
      onDrawerChanged: (_) => setState(() {}),
      drawer: !wide || drawerOpen
          ? Drawer(child: _buildMenu(closeDrawer: true))
          : null,
      body: _controller.loadError != null
          ? Center(child: Text('Error loading notes: ${_controller.loadError}'))
          : _controller.isLoading && _controller.noteData.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _controller.noteData.isEmpty
          ? Center(
              child: Text(
                _controller.category == NoteCategory.trashed
                    ? 'Trash is empty'
                    : 'No notes yet',
              ),
            )
          : NoteList(
              noteData: _controller.noteData,
              order: _controller.order,
              openNote: _openNote,
            ),
    );
  }

  Widget _buildMenu({required bool closeDrawer}) {
    return SafeArea(
      child: ListView(
        primary: false,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final (category, label, icon) in [
            (NoteCategory.active, 'Notes', Icons.notes),
            (NoteCategory.trashed, 'Trash', Icons.delete_outline),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              selected: _controller.category == category,
              onTap: () {
                if (closeDrawer) _scaffoldKey.currentState?.closeDrawer();
                unawaited(_controller.setCategory(category));
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              if (closeDrawer) _scaffoldKey.currentState?.closeDrawer();
              unawaited(_openSettings());
            },
          ),
        ],
      ),
    );
  }
}
