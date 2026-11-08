import 'package:flutter/material.dart';
import 'package:notes/screens/home/note_search_controller.dart';
import 'package:notes/screens/home/widget/note_list.dart';
import 'package:notes_app/notes_app.dart';

/// Displays the current search snapshot in relevance order.
class NoteSearchView extends StatelessWidget {
  final NoteSearchController controller;
  final Future<void> Function(String? noteId) openNote;

  const NoteSearchView({
    super.key,
    required this.controller,
    required this.openNote,
  });

  @override
  Widget build(BuildContext context) {
    if (controller.readinessError != null || controller.searchError != null) {
      return const Center(child: Text('Unable to search notes'));
    }
    const loading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 8),
        Text('Loading search'),
      ],
    );
    if (!controller.hasSnapshot) {
      return controller.isLoading
          ? const Center(child: loading)
          : const SizedBox.shrink();
    }
    return Column(
      children: [
        controller.isLoading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Align(alignment: Alignment.centerLeft, child: loading),
              )
            : const SizedBox.shrink(),
        Expanded(
          child: controller.results.isEmpty
              ? const Center(child: Text('No matching notes'))
              : NoteList(
                  noteData: controller.results,
                  order: NoteSortOrder.updatedAtDescending,
                  showTrashMarker: true,
                  openNote: openNote,
                ),
        ),
      ],
    );
  }
}
