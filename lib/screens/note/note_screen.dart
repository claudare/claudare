import 'package:flutter/material.dart';
import 'package:notes_app_v0/common.dart';
import 'package:notes_app_v0/runtime/notes_runtime.dart';
import 'package:notes_app_v0/screens/note/note_controller.dart';

class NoteScreen extends StatefulWidget {
  final NotesRuntime notesRuntime;

  final String? noteId;

  const NoteScreen({
    super.key,
    required this.noteId,
    required this.notesRuntime,
  });

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late NoteController _controller;

  late TextEditingController _titleController;
  late FocusNode _titleFocus;

  late TextEditingController _contentController;
  late FocusNode _contentFocus;

  bool _flushed = true;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: '');
    _titleController.addListener(_onTitleTextChange);

    _titleFocus = FocusNode();
    _titleFocus.addListener(_onTitleFocusChange);
    _titleFocus.onKeyEvent = (node, event) {
      // print(
      //   'title focus event: node.hasFocus ${node.hasFocus} key: ${event.logicalKey}',
      // );
      return KeyEventResult.ignored;
    };

    _contentController = TextEditingController(text: '');
    _contentController.addListener(_onContentTextChange);

    _contentFocus = FocusNode();
    _contentFocus.addListener(_onContentFocusChange);
    _contentFocus.onKeyEvent = (node, event) {
      // print(
      //   'content focus event: node.hasFocus ${node.hasFocus} key: ${event.logicalKey}',
      // );
      return KeyEventResult.ignored;
    };

    _controller = NoteController(widget.notesRuntime);
    _controller.addListener(() => setState(() {}));

    _controller.load(widget.noteId).then((values) {
      _titleController.text = values.title;
      _contentController.text = values.content;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();

    _contentController.dispose();
    _contentFocus.dispose();

    _controller.dispose();

    super.dispose();
  }

  void _markDirty() {
    _flushed = false;
  }

  void _onTitleTextChange() {
    _markDirty();
    _controller.submitTitleChange(_titleController.text);
  }

  void _onTitleFocusChange() {
    if (!_titleFocus.hasFocus) {
      _flushChanges();
    }
  }

  void _onContentTextChange() {
    _markDirty();
    _controller.submitContentChange(_contentController.text);
  }

  void _onContentFocusChange() {
    if (!_contentFocus.hasFocus) {
      _flushChanges();
    }
  }

  Future<void> _flushChanges() async {
    if (_flushed) return;
    _flushed = true;

    try {
      final applied = await _controller.flushChanges();
      if (!applied) return;

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Note saved'), duration: Duration(seconds: 1)),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving note: $e'),
          duration: Duration(seconds: 10),
        ),
      );
    }
  }

  Future<void> _trashNote() async {
    try {
      final trashed = await _controller.trash();
      if (!trashed) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Note deleted'), duration: Duration(seconds: 1)),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting note: $e'),
          duration: Duration(seconds: 10),
        ),
      );
    }
  }

  Future<void> _restoreNote() async {
    try {
      final restored = await _controller.restore();
      if (!restored) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Note restored'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error restoring note: $e'),
          duration: Duration(seconds: 10),
        ),
      );
    }
  }

  void _onPopInvokedWithResult() async {
    print('invoking pop with result');
    await _flushChanges();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _onPopInvokedWithResult(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _controller.isTrashed ? 'Viewing deleted note' : 'Editing note',
          ),
          actions: [
            // IconButton(
            //   icon: Icon(Icons.tag),
            //   onPressed: () => _onTagPressed(context),
            // ),
            _controller.isTrashed
                ? IconButton(
                  icon: Icon(Icons.restore),
                  onPressed:
                      _controller.isTrashed ? () => _restoreNote() : null,
                )
                : IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () => _trashNote(),
                ),
            // IconButton(
            //   icon: Icon(Icons.save),
            //   onPressed:
            //       _textContentChanged
            //           ? () => _saveNote(controller, updateState: true)
            //           : null,
            //   tooltip:
            //       _textContentChanged
            //           ? 'Save changes'
            //           : 'All changes upto date',
            //   disabledColor: _textContentChanged ? null : Colors.red,
            // ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: 'Enter note title...',
                  border: OutlineInputBorder(),
                ),
                focusNode: _titleFocus,
                // TODO: this breaks tab order, sometimes
                enabled: !_controller.isBusy && !_controller.isTrashed,
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
                  focusNode: _contentFocus,
                  // TODO: this breaks tab order, sometimes
                  enabled: !_controller.isBusy && !_controller.isTrashed,
                ),
              ),
              SizedBox(height: 4),

              Row(
                spacing: 8.0,
                children: [
                  Text(
                    'Created at ${formatDateTime(_controller.createdAt)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    'Updated at ${formatDateTime(_controller.updatedAt)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  _controller.trashedAt != null
                      ? Text(
                        'Deleted at ${formatDateTime(_controller.trashedAt!)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      )
                      : SizedBox.shrink(),
                ],
              ),

              // only show below if tags are present... what a wierd syntax
              // if (widget.note.tags.isNotEmpty) SizedBox(height: 8),
              // Wrap(
              //   spacing: 4.0,
              //   runSpacing: 4.0,
              //   children:
              //       widget.note.tags.map((tagName) {
              //         return TagWidget(
              //           tagName: tagName,
              //           onRemove: (value) => _unassignTag(controller, value),
              //         );
              //       }).toList(),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
