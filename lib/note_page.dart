import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notes_app_v0/repo.dart';

class NotePage extends StatefulWidget {
  final Repo repo;
  final NoteData note;

  const NotePage({super.key, required this.repo, required this.note});

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
  bool _contentChanged = false;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: widget.note.title);
    _titleController.addListener(_onNoteChanged);
    _contentController = TextEditingController(text: widget.note.content);
    _contentController.addListener(_onNoteChanged);
  }

  void _onNoteChanged() {
    // print('Note changed');
    // TextEditingDelta(oldText: _titleController.text, selection: _titleController.selection, composing: _titleController.tex)
    setState(() {
      _contentChanged = _didTitleChange() || _didContentChange();
    });
  }

  @override
  void didUpdateWidget(NotePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id) {
      _titleController.text = widget.note.title;
      _contentController.text = widget.note.content;
      _contentChanged = false;
    }
  }

  bool _didTitleChange() {
    return _titleController.text != widget.note.title;
  }

  bool _didContentChange() {
    return _contentController.text != widget.note.content;
  }

  void _saveNote() {
    if (_didTitleChange()) {
      widget.repo.processEvent(
        NoteTitleUpdated(widget.note.id, _titleController.text),
        DateTime.now(),
      );
    }
    if (_didContentChange()) {
      widget.repo.processEvent(
        NoteContentUpdated(widget.note.id, _contentController.text),
        DateTime.now(),
      );
    }

    // _contentController.text = "lalala mutated";
    setState(() {
      _contentChanged = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Note saved')));
  }

  @override
  void dispose() {
    _titleController.removeListener(_onNoteChanged);
    _titleController.dispose();
    _contentController.removeListener(_onNoteChanged);
    _contentController.dispose();

    super.dispose();
  }

  void _onPopInvokedWithResult(bool didPop, _) async {
    if (_contentChanged) {
      _saveNote();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: _onPopInvokedWithResult,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.note.title.isEmpty ? 'Edit Note' : widget.note.title,
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.save),
              onPressed: _contentChanged ? _saveNote : null,
              tooltip:
                  _contentChanged ? 'Save changes' : 'All changes upto date',
              disabledColor: _contentChanged ? null : Colors.red,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Created: ${_formatDateTime(widget.note.createdAt)}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                'Last updated: ${_formatDateTime(widget.note.updatedAt)}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              SizedBox(height: 16),
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
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
