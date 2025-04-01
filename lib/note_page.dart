import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notes_app_v0/common.dart';
import 'package:notes_app_v0/controller.dart';
import 'package:notes_app_v0/events.dart';
import 'package:notes_app_v0/repo.dart';
import 'package:notes_app_v0/controller_provider.dart';
import 'package:notes_app_v0/tag_widget.dart';
import 'package:notes_app_v0/tags_manager.dart';

class NotePage extends StatefulWidget {
  final NoteData note;

  const NotePage({super.key, required this.note});

  @override
  State<NotePage> createState() => _NotePageState();
}

// granular updates to text inputs are not supported... wtf??? cant capture inputs???
// https://github.com/flutter/flutter/issues/87972#issuecomment-935114217
// apparently TextEditingDeltas is now available, but how to use it?
// anyways, markdown is needed, so try later this library:
// https://pub.dev/packages/markdown_widget
// the text content can be updated by just setting the contentController.text
// manual delta extraction and application will be such a pain in the ass
// maybe find an alternative library that supports granular updates or implements
// custom logic to handle text changes efficiently.
class _NotePageState extends State<NotePage> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late StreamSubscription<void> _changesSubscription;
  bool _textContentChanged = false;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: widget.note.title);
    _titleController.addListener(_onTextContentChanged);
    _contentController = TextEditingController(text: widget.note.content);
    _contentController.addListener(_onTextContentChanged);

    final changes = widget.note.changes;
    _changesSubscription = changes.listen((event) {
      if (!context.mounted) {
        throw Exception('Context was not mounted???');
      }

      _onTextContentChanged(); // forces full ui refresh

      // do not update the text for now... in the future
      // this will be an intelligent choice
      // _titleController.text = widget.note.title;
      // _contentController.text = widget.note.content;
    });
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTextContentChanged);
    _titleController.dispose();
    _contentController.removeListener(_onTextContentChanged);
    _contentController.dispose();

    _changesSubscription.cancel();

    super.dispose();
  }

  void _onTextContentChanged() {
    // print('Note changed');
    // TextEditingDelta(oldText: _titleController.text, selection: _titleController.selection, composing: _titleController.tex)
    setState(() {
      _textContentChanged = _didTitleChange() || _didContentChange();
    });
  }

  @override
  void didUpdateWidget(NotePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id) {
      _titleController.text = widget.note.title;
      _contentController.text = widget.note.content;
      _textContentChanged = false;
    }
  }

  bool _didTitleChange() {
    return _titleController.text != widget.note.title;
  }

  bool _didContentChange() {
    return _contentController.text != widget.note.content;
  }

  void _saveNote(Controller controller, {bool updateState = true}) {
    if (_didTitleChange()) {
      controller.localEventSubmit(
        NoteTitleUpdated(widget.note.id, _titleController.text),
      );
    }
    if (_didContentChange()) {
      controller.localEventSubmit(
        NoteContentUpdated(widget.note.id, _contentController.text),
      );
    }

    if (updateState) {
      setState(() {
        _textContentChanged = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Note saved')));
    }
  }

  Future<void> _deleteNote(BuildContext ctx, Controller controller) async {
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text('Delete note?'),
                content: Text('Are you sure you want to delete this note?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('No'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text('Yes'),
                  ),
                ],
              ),
        ) ??
        false;

    if (shouldDelete) {
      controller.localEventSubmit(NoteDeleted(widget.note.id));
      // prevent saving it ???
      setState(() {
        _textContentChanged = false;
      });
      if (ctx.mounted) {
        Navigator.of(ctx).pop();
      }
    }
  }

  void _unassignTag(Controller controller, String tag) {
    controller.localEventSubmit(TagUnassigned(widget.note.id, tag));
  }

  Future<void> _onTagPressed(BuildContext context) async {
    // this doesnt need await though?
    await showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
      builder: (context) {
        return TagsManager(noteData: widget.note);
      },
    );

    // normal dialogs are out of my competence haha
    // await showDialog(
    //   context: context,
    //   builder: (context) {
    //     return AlertDialog(
    //       title: Text('Manage Tags'),
    //       content: TagsManager(repo: widget.repo, noteData: widget.note),
    //     );
    //   },
    // );
  }

  void _onPopInvokedWithResult(Controller controller, bool didPop) async {
    if (_textContentChanged) {
      print('autosaving note onPop, didPop: $didPop');
      _saveNote(controller, updateState: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ControllerProvider.of(context);
    return PopScope(
      onPopInvokedWithResult:
          (didPop, _) => _onPopInvokedWithResult(controller, didPop),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.note.title.isEmpty ? 'Edit Note' : widget.note.title,
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.tag),
              onPressed: () => _onTagPressed(context),
            ),
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: () => _deleteNote(context, controller),
            ),
            IconButton(
              icon: Icon(Icons.save),
              onPressed:
                  _textContentChanged
                      ? () => _saveNote(controller, updateState: true)
                      : null,
              tooltip:
                  _textContentChanged
                      ? 'Save changes'
                      : 'All changes upto date',
              disabledColor: _textContentChanged ? null : Colors.red,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Created: ${formatDateTime(widget.note.createdAt.toDateTime())}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                'Last updated: ${formatDateTime(widget.note.updatedAt.toDateTime())}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),

              SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: 'Enter note title...',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _contentController,
                  maxLines: null,
                  expands: true,
                  decoration: InputDecoration(
                    hintText: 'Enter note content...',
                    border: OutlineInputBorder(),
                  ),
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
              // only show below if tags are present... what a wierd syntax
              if (widget.note.tags.isNotEmpty) SizedBox(height: 8),
              Wrap(
                spacing: 4.0,
                runSpacing: 4.0,
                children:
                    widget.note.tags.map((tagName) {
                      return TagWidget(
                        tagName: tagName,
                        onRemove: (value) => _unassignTag(controller, value),
                      );
                    }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
