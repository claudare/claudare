import 'package:flutter/material.dart';
import 'package:notes_app_v0/application/application_provider.dart';
import 'package:notes_app_v0/command/create_note.dart';
import 'package:notes_app_v0/command/delete_note.dart';
import 'package:notes_app_v0/command/update_note_content.dart';
import 'package:notes_app_v0/command/update_note_title.dart';
import 'package:notes_app_v0/common.dart';
import 'package:notes_app_v0/model/note_data.dart';

class NoteScreen extends StatefulWidget {
  final String? noteId;

  const NoteScreen({super.key, required this.noteId});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late TextEditingController _titleController;
  late FocusNode _titleFocus;

  late TextEditingController _contentController;
  late FocusNode _contentFocus;

  bool _isBusy = true;
  String? _noteId;
  String _prevTitle = '';
  String _prevContent = '';

  @override
  void initState() {
    super.initState();

    _noteId = widget.noteId;

    // It is very important that actual content of this preview aligns with
    // the value of CRDT exactly.
    // For now its set to empty, will be set after load.
    _titleController = TextEditingController(text: '');
    _titleFocus = FocusNode();
    _titleFocus.addListener(_onTitleFocusChange);
    _titleFocus.onKeyEvent = (node, event) {
      print(
        'title focus event: node.hasFocus ${node.hasFocus} key: ${event.logicalKey}',
      );
      return KeyEventResult.ignored;
    };

    _contentController = TextEditingController(text: '');
    _contentFocus = FocusNode();
    _contentFocus.addListener(_onContentFocusChange);
    _contentFocus.onKeyEvent = (node, event) {
      print(
        'content focus event: node.hasFocus ${node.hasFocus} key: ${event.logicalKey}',
      );
      return KeyEventResult.ignored;
    };
  }

  void _onTitleFocusChange() {
    print('title focus changed: ${_titleFocus.hasFocus}');

    if (!_titleFocus.hasFocus) {
      // meaning we were let go
      // try to save the changes
      _saveChanges();
    }
  }

  void _onContentFocusChange() {
    print('content focus changed: ${_contentFocus.hasFocus}');

    if (!_contentFocus.hasFocus) {
      // meaning we were let go
      // try to save the changes
      _saveChanges();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    print('NoteScreen didChangeDependencies');

    _loadNote();
  }

  Future<void> _loadNote() async {
    // load everything based on the note
    //

    try {
      if (_noteId == null) return;

      final application = ApplicationProvider.of(context);

      final note = await application.notesRuntime.noteReadModel.getNote(
        _noteId!,
      );
      if (note == null) return;

      setState(() {
        _prevTitle = note.title.value;
        _prevContent = note.content;
      });

      // update the controllers
      _titleController.text = note.title.value;
      _contentController.text = note.content;
    } catch (e) {
      print('Failed to load note: $e');
    } finally {
      setState(() {
        _isBusy = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
    });

    // early exit if nothing was created
    if (_noteId == null &&
        _titleController.text == '' &&
        _contentController.text == '') {
      setState(() {
        _isBusy = false;
      });
      return;
    }

    try {
      int changeCount = 0;
      final application = ApplicationProvider.of(context);

      final noteId = _noteId ?? application.idGenerator.generateId();

      if (_noteId == null) {
        // create the note
        setState(() {
          _noteId = noteId;
          _prevTitle = '';
          _prevContent = '';
        });

        await application.notesRuntime.commands.createNote.runThrowable(
          CreateNoteInput(noteId: noteId),
        );
        changeCount++;
      }

      final prevTitle = _prevTitle;
      final newTitle = _titleController.text;
      if (newTitle != prevTitle) {
        await application.notesRuntime.commands.updateNoteTitle.runThrowable(
          UpdateNoteTitleInput(noteId: noteId, fullValue: newTitle),
        );

        setState(() {
          _prevTitle = newTitle;
        });
        changeCount++;
      }

      final initialContent = _prevContent;
      final newContent = _contentController.text;
      if (newContent != initialContent) {
        await application.notesRuntime.commands.updateNoteContent.runThrowable(
          UpdateNoteContentInput(noteId: noteId, overrideContent: newContent),
        );

        setState(() {
          _prevContent = newContent;
        });
        changeCount++;
      }

      if (!mounted) {
        print('not mounted when trying to show a snackbar');
        return;
      }
      if (changeCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Note saved'), duration: Duration(seconds: 1)),
        );
      }
      // else {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     SnackBar(
      //       content: Text('No note changes'),

      //       duration: Duration(seconds: 1),
      //     ),
      //   );
      // }
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving note: $e'),
          duration: Duration(seconds: 1),
        ),
      );
    } finally {
      setState(() {
        _isBusy = false;
      });
    }
  }

  Future<void> _deleteNote() async {
    if (_noteId == null) {
      Navigator.of(context).pop();
      return;
    }

    try {
      final application = ApplicationProvider.of(context);
      await application.notesRuntime.commands.deleteNote.runThrowable(
        DeleteNoteInput(noteId: _noteId!),
      );
      if (!mounted) {
        return;
      }
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
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _onPopInvokedWithResult() async {
    await _saveChanges();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();

    _contentController.dispose();
    _contentFocus.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _onPopInvokedWithResult(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Editing note'),
          actions: [
            // IconButton(
            //   icon: Icon(Icons.tag),
            //   onPressed: () => _onTagPressed(context),
            // ),
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: () => _deleteNote(),
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
              // Text(
              //   'Created: ${formatDateTime(widget.note.createdAt.toDateTime())}',
              //   style: TextStyle(fontSize: 12, color: Colors.grey),
              // ),
              // Text(
              //   'Last updated: ${formatDateTime(widget.note.updatedAt.toDateTime())}',
              //   style: TextStyle(fontSize: 12, color: Colors.grey),
              // ),
              SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: 'Enter note title...',
                  border: OutlineInputBorder(),
                ),
                focusNode: _titleFocus,
                enabled: !_isBusy,
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
                  enabled: !_isBusy,
                ),
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
