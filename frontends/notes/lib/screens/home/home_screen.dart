import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/layout_breakpoints.dart';
import 'package:notes/screens/home/note_list_controller.dart';
import 'package:notes/screens/home/note_search_controller.dart';
import 'package:notes/screens/home/note_search_view.dart';
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
  late NoteSearchController _searchController;
  final _searchText = TextEditingController();
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
      _searchController.removeListener(_onControllerChanged);
      _searchController.dispose();
    }
    _application = application;
    _controller = NoteListController(application);
    _controller.addListener(_onControllerChanged);
    _searchText.clear();
    _searchController = NoteSearchController(application);
    _searchController.addListener(_onControllerChanged);
    unawaited(_controller.reloadNotes());
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _searchController.removeListener(_onControllerChanged);
    _searchController.dispose();
    _searchText.dispose();
    super.dispose();
  }

  Future<void> _openNote(String? noteId) async {
    _clearSearch();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => NoteScreen(noteId: noteId)));
    if (mounted) await _controller.reloadNotes();
  }

  Future<void> _openSettings() async {
    _clearSearch();
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
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Row(
                        children: [
                          Expanded(child: _buildMenu(closeDrawer: false)),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ],
                      ),
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
        title: SearchBar(
          controller: _searchText,
          onChanged: _searchController.setQuery,
          hintText: 'Search note contents',
          constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
          elevation: const WidgetStatePropertyAll(0),
          leading: const Icon(Icons.search),
          trailing: [
            if (_searchController.query.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.clear),
                onPressed: _clearSearch,
              ),
          ],
        ),
        actions: [
          PopupMenuButton<NoteSortOrder>(
            tooltip: 'Sort notes',
            icon: const Icon(Icons.sort),
            enabled: !_controller.isLoading && !_searchController.hasQuery,
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
      body: _buildResults(),
    );
  }

  void _clearSearch() {
    _searchText.clear();
    _searchController.setQuery('');
    FocusScope.of(context).focusedChild?.unfocus();
  }

  Widget _buildResults() {
    if (_searchController.hasQuery) {
      return NoteSearchView(controller: _searchController, openNote: _openNote);
    }
    return _buildNoteList();
  }

  Widget _buildNoteList() {
    if (_controller.loadError != null) {
      return Center(
        child: Text('Error loading notes: ${_controller.loadError}'),
      );
    }
    if (_controller.isLoading && _controller.noteData.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.noteData.isEmpty) {
      return Center(
        child: Text(
          _controller.category == NoteCategory.trashed
              ? 'Trash is empty'
              : 'No notes yet',
        ),
      );
    }
    return NoteList(
      noteData: _controller.noteData,
      order: _controller.order,
      openNote: _openNote,
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
                _clearSearch();
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
