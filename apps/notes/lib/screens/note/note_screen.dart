import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/common.dart';
import 'package:notes/screens/note/note_controller.dart';

class NoteScreen extends StatefulWidget {
  final String? noteId;

  const NoteScreen({super.key, required this.noteId});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late NoteController _controller;
  NoteApplication? _application;

  late TextEditingController _titleController;
  late FocusNode _titleFocus;

  late TextEditingController _contentController;
  late FocusNode _contentFocus;

  Future<bool>? _flushInProgress;
  bool _flushAgain = false;
  bool _allowPop = false;
  bool _leaving = false;
  Exception? _loadError;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: '');
    _titleController.addListener(_onTitleTextChange);

    _titleFocus = FocusNode();
    _titleFocus.addListener(_onTitleFocusChange);
    _titleFocus.onKeyEvent = (node, event) {
      return KeyEventResult.ignored;
    };

    _contentController = TextEditingController(text: '');
    _contentController.addListener(_onContentTextChange);

    _contentFocus = FocusNode();
    _contentFocus.addListener(_onContentFocusChange);
    _contentFocus.onKeyEvent = (node, event) {
      return KeyEventResult.ignored;
    };
  }

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
    _controller = NoteController(application);
    _controller.addListener(_onControllerChanged);
    _flushInProgress = null;
    _flushAgain = false;
    _allowPop = false;
    _leaving = false;
    _loadError = null;
    _titleController.clear();
    _contentController.clear();
    unawaited(_loadNote(_controller));
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadNote(NoteController controller) async {
    try {
      final values = await controller.load(widget.noteId);
      if (!mounted || !identical(controller, _controller)) return;
      _titleController.text = values.title;
      _contentController.text = values.content;
    } on Exception catch (error) {
      if (mounted && identical(controller, _controller)) {
        setState(() => _loadError = error);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();

    _contentController.dispose();
    _contentFocus.dispose();

    _controller.removeListener(_onControllerChanged);
    _controller.dispose();

    super.dispose();
  }

  void _onTitleTextChange() {
    _controller.submitTitleChange(_titleController.text);
  }

  void _onTitleFocusChange() {
    if (!_titleFocus.hasFocus) {
      unawaited(_flushChanges());
    }
  }

  void _onContentTextChange() {
    _controller.submitContentChange(_contentController.text);
  }

  void _onContentFocusChange() {
    if (!_contentFocus.hasFocus) {
      unawaited(_flushChanges());
    }
  }

  Future<bool> _flushChanges() async {
    final active = _flushInProgress;
    if (active != null) {
      _flushAgain = true;
      return active;
    }

    final flush = _runFlush(_controller);
    _flushInProgress = flush;
    try {
      return await flush;
    } finally {
      if (identical(_flushInProgress, flush)) _flushInProgress = null;
    }
  }

  Future<bool> _runFlush(NoteController controller) async {
    try {
      var applied = false;
      while (true) {
        if (!identical(controller, _controller)) return false;
        _flushAgain = false;
        final revision = controller.editRevision;
        applied = await controller.flushChanges() || applied;
        if (!identical(controller, _controller)) return false;
        if (!_flushAgain && controller.editRevision == revision) break;
      }
      if (!applied) return true;

      if (mounted && identical(controller, _controller)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note saved'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return true;
    } on Exception catch (e) {
      if (mounted && identical(controller, _controller)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving note: $e'),
            duration: const Duration(seconds: 10),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _trashNote() async {
    final controller = _controller;
    try {
      if (!await _flushChanges()) return;
      if (!identical(controller, _controller)) return;
      final trashed = await controller.trash();
      if (!trashed) return;

      if (!mounted || !identical(controller, _controller)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Note deleted'), duration: Duration(seconds: 1)),
      );
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    } on Exception catch (e) {
      if (!mounted || !identical(controller, _controller)) {
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
    final controller = _controller;
    try {
      final restored = await controller.restore();
      if (!restored) return;

      if (!mounted || !identical(controller, _controller)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Note restored'),
          duration: Duration(seconds: 1),
        ),
      );
    } on Exception catch (e) {
      if (!mounted || !identical(controller, _controller)) {
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

  Future<void> _onPopInvokedWithResult(bool didPop) async {
    if (didPop || _leaving) return;

    final controller = _controller;
    _leaving = true;
    try {
      if (!await _flushChanges() || !mounted) return;
      if (!identical(controller, _controller)) return;
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    } finally {
      if (identical(controller, _controller)) _leaving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) => _onPopInvokedWithResult(didPop),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _controller.isTrashed ? 'Viewing deleted note' : 'Editing note',
          ),
          actions: [
            _controller.isTrashed
                ? IconButton(
                  icon: Icon(Icons.restore),
                  onPressed:
                      _controller.isTrashed ? () => _restoreNote() : null,
                )
                : IconButton(
                  icon: Icon(Icons.delete),
                  onPressed:
                      _controller.exists && !_controller.isLoading
                          ? () => _trashNote()
                          : null,
                ),
          ],
        ),
        body:
            _loadError == null
                ? _buildEditor()
                : Center(child: Text('Error loading note: $_loadError')),
      ),
    );
  }

  Widget _buildEditor() {
    return Padding(
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
            enabled: !_controller.isLoading && !_controller.isTrashed,
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
              enabled: !_controller.isLoading && !_controller.isTrashed,
            ),
          ),
          SizedBox(height: 4),
          Wrap(
            spacing: 8.0,
            children: [
              if (_controller.createdAt != null)
                Text(
                  'Created at ${formatDateTime(_controller.createdAt!)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              if (_controller.updatedAt != null)
                Text(
                  'Updated at ${formatDateTime(_controller.updatedAt!)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              if (_controller.trashedAt != null)
                Text(
                  'Deleted at ${formatDateTime(_controller.trashedAt!)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
