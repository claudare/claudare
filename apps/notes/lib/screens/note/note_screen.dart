import 'dart:async';

import 'package:crdt/crdt_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/common.dart';
import 'package:notes/screens/note/note_controller.dart';
import 'package:notes/screens/note/note_content_simulation.dart';
import 'package:notes/screens/note/flutter_crdt_text_controller.dart';

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
  CrdtTextBinding? _contentBinding;
  late NoteContentSimulation _simulation;
  Future<void>? _refreshInProgress;

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
      _simulation.dispose();
      _contentBinding?.dispose();
      _contentBinding = null;
      _controller.removeListener(_onControllerChanged);
      _controller.dispose();
    }
    _application = application;
    _controller = NoteController(application);
    _simulation = NoteContentSimulation(
      controller: _controller,
      onPersisted: _refreshAfterSimulatedEdit,
      onError: _onSimulationError,
    );
    _controller.addListener(_onControllerChanged);
    _flushInProgress = null;
    _refreshInProgress = null;
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
      _contentBinding = CrdtTextBinding(
        editContext: controller.content,
        controller: FlutterCrdtTextController(_contentController),
      );
    } on Exception catch (error) {
      if (mounted && identical(controller, _controller)) {
        setState(() => _loadError = error);
      }
    }
  }

  @override
  void dispose() {
    _simulation.dispose();
    _contentBinding?.dispose();
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

  void _onContentFocusChange() {
    if (!_contentFocus.hasFocus) {
      unawaited(_flushChanges());
    }
  }

  Future<bool> _flushChanges({bool showNothingToSave = false}) async {
    final controller = _controller;
    await _refreshInProgress;
    if (!mounted || !identical(controller, _controller)) return false;
    final active = _flushInProgress;
    if (active != null) {
      _flushAgain = true;
      return active;
    }

    final flush = _runFlush(controller, showNothingToSave: showNothingToSave);
    _flushInProgress = flush;
    try {
      return await flush;
    } finally {
      if (identical(_flushInProgress, flush)) _flushInProgress = null;
    }
  }

  Future<bool> _runFlush(
    NoteController controller, {
    required bool showNothingToSave,
  }) async {
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
      if (!applied) {
        if (showNothingToSave && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nothing to save'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        return true;
      }

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
    setState(_simulation.stop);
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
    if (mounted) setState(_simulation.stop);
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

  void _toggleSimulation(bool enabled) {
    setState(() {
      if (enabled) {
        _simulation.start();
      } else {
        _simulation.stop();
      }
    });
  }

  void _onSimulationError(Exception error) {
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Error simulating edit: $error')));
  }

  Future<void> _refreshAfterSimulatedEdit() async {
    final controller = _controller;
    await _refreshInProgress;
    if (!mounted || _leaving || !identical(controller, _controller)) return;
    await _refreshNote();
  }

  Future<void> _refreshNote() async {
    if (_refreshInProgress != null) return;
    final controller = _controller;
    final refresh = _runRefresh(controller, _flushInProgress);
    setState(() {
      _refreshInProgress = refresh;
    });
    try {
      await refresh;
    } finally {
      if (mounted && identical(_refreshInProgress, refresh)) {
        setState(() => _refreshInProgress = null);
      }
    }
  }

  Future<void> _runRefresh(
    NoteController controller,
    Future<bool>? saving,
  ) async {
    try {
      await saving;
      if (!mounted || !identical(controller, _controller)) return;
      await controller.refresh();
      if (!mounted || !identical(controller, _controller)) return;
      if (controller.isTrashed) setState(_simulation.stop);
    } on Exception catch (error) {
      if (mounted && identical(controller, _controller)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing note: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(
              LogicalKeyboardKey.keyS,
              control: true,
              includeRepeats: false,
            ):
            _SaveNoteIntent(),
      },
      child: Actions(
        actions: {
          _SaveNoteIntent: CallbackAction<_SaveNoteIntent>(
            onInvoke: (_) {
              unawaited(_flushChanges(showNothingToSave: true));
              return null;
            },
          ),
        },
        child: PopScope(
          canPop: _allowPop,
          onPopInvokedWithResult:
              (didPop, _) => _onPopInvokedWithResult(didPop),
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                _controller.isTrashed ? 'Viewing deleted note' : 'Editing note',
              ),
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed:
                      _controller.exists &&
                              !_controller.isLoading &&
                              _refreshInProgress == null
                          ? _refreshNote
                          : null,
                ),
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
        ),
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
          SwitchListTile(
            title: const Text('Simulate external edits'),
            value: _simulation.isRunning,
            onChanged:
                _controller.exists &&
                        !_controller.isLoading &&
                        !_controller.isTrashed
                    ? _toggleSimulation
                    : null,
          ),
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

class _SaveNoteIntent extends Intent {
  const _SaveNoteIntent();
}
