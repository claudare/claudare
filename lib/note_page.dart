import 'package:flutter/material.dart';
import 'package:notes_app_v0/repo.dart';

class NotePage extends StatefulWidget {
  final Repo repo;
  final NoteData note;

  const NotePage({super.key, required this.repo, required this.note});

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  late TextEditingController _contentController;
  bool _contentChanged = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.note.content);
    _contentController.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    setState(() {
      _contentChanged = _contentController.text != widget.note.content;
    });
  }

  @override
  void didUpdateWidget(NotePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id) {
      _contentController.text = widget.note.content;
      _contentChanged = false;
    }
  }

  void _saveNote() {
    widget.repo.processEvent(
      NoteBodyUpdated(widget.note.id, _contentController.text),
      DateTime.now(),
    );
    setState(() {
      _contentChanged = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Note saved')));
  }

  @override
  void dispose() {
    _contentController.removeListener(_onContentChanged);
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.note.title.isEmpty ? 'Edit Note' : widget.note.title,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _contentChanged ? _saveNote : null,
            tooltip: _contentChanged ? 'Save changes' : 'All changes upto date',
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
            Expanded(
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  hintText: 'Enter note content...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
