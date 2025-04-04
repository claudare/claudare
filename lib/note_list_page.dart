import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:notes_app_v0/common.dart';
import 'package:notes_app_v0/events.dart';
import 'package:notes_app_v0/note_page.dart';
import 'package:notes_app_v0/repo.dart';
import 'package:notes_app_v0/controller_provider.dart';
import 'package:notes_app_v0/settings_page.dart';

class NoteListPage extends StatefulWidget {
  const NoteListPage({super.key});

  @override
  _NoteListPageState createState() => _NoteListPageState();
}

// does this really need to be Stateful?
class _NoteListPageState extends State<NoteListPage> {
  // add text controller for search
  bool _isSearching = false;

  void _openSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SettingsPage()));
  }

  void _openNote(BuildContext context, NoteData note) async {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => NotePage(note: note)));
  }

  Future<void> _newNote(BuildContext context) async {
    final controller = ControllerProvider.of(context);

    final noteId = controller.newGenericId('note');
    await controller.localEventSubmit(NoteCreated(noteId));

    // this could be racy
    final note = await controller.repo.getNote(noteId);
    if (note == null) {
      throw Exception('new note could not be loaded??');
    }

    if (context.mounted) {
      _openNote(context, note);
    }
  }

  Future<void> _onSearchTextChange(Repo repo, String query) async {
    final isSearching = query.isNotEmpty;

    await repo.searchNote(query);
    setState(() {
      _isSearching = isSearching;
    });

    // new order for search

    // print('text chhanged to ${_searchController.text}');
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ControllerProvider.of(context).repo;

    return Scaffold(
      appBar: AppBar(
        title: Text('Notes'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => _openSettings(context),
          ),
          IconButton(icon: Icon(Icons.add), onPressed: () => _newNote(context)),
        ],
      ),

      body: Column(
        // add a search bar inside children
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search notes...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (text) {
                _onSearchTextChange(repo, text);
              },
            ),
          ),
          Expanded(
            child:
                _isSearching
                    ? ResultList(
                      order: repo.searchOrder,
                      getNote: repo.getNote,
                      openNote: _openNote,
                    )
                    : ResultList(
                      order: repo.order,
                      getNote: repo.getNote,
                      openNote: _openNote,
                    ),
          ),
        ],
      ),
    );
  }
}

// add function Future<NoteData?> getNote(GenericId id) to constructor
class ResultList extends StatelessWidget {
  const ResultList({
    super.key,
    required this.order,
    required this.getNote,
    required this.openNote,
  });

  final NoteOrderData order;
  final Function(BuildContext context, NoteData note) openNote;
  final Future<NoteData?> Function(GenericId id) getNote;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: order.changes,
      builder: (context, snapshot) {
        return ListView.builder(
          itemCount: order.items.length,
          itemBuilder: (context, index) {
            final id = order.items[index];
            return FutureBuilder(
              future: getNote(id),
              builder: (context, snapshot) {
                final note = snapshot.data;

                if (note == null) {
                  return SizedBox.shrink();
                }

                return StreamBuilder<void>(
                  stream: note.changes,
                  builder: (context, snapshot) {
                    return ListTile(
                      title: Text(note.title.isEmpty ? 'No title' : note.title),
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
                      onTap: () => openNote(context, note),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
