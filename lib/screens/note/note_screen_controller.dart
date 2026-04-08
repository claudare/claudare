// WIP

// import 'package:flutter/material.dart';
// import 'package:notes_app_v0/command/create_note.dart';
// import 'package:notes_app_v0/command/update_note_title.dart';
// import 'package:notes_app_v0/model/note_data.dart';
// import 'package:notes_app_v0/runtime/notes_runtime.dart';

// class NoteScreenController extends ChangeNotifier {
//   final NotesRuntime notesRuntime;

//   NoteData? _latestData;
//   bool _isBusy = false;

//   NoteScreenController(this.notesRuntime);

//   NoteData? get lastData => _latestData;

//   Future<void> load(String? noteId) async {
//     if (noteId == null) return;

//     _isBusy = true;
//     notifyListeners();

//     try {
//       _latestData = await notesRuntime.resolvedNoteReadModel.getNote(noteId);
//     } finally {
//       _isBusy = false;
//       notifyListeners();
//     }
//   }

//   Future<void> _ensureNoteIsCreated() async {
//     if (_latestData != null) {
//       return;
//     }

//     final noteId = notesRuntime.idGenerator.generateId();
//     await notesRuntime.commands.createNote.runThrowable(
//       CreateNoteInput(noteId: noteId),
//     );

//     _latestData = await notesRuntime.resolvedNoteReadModel.getNote(noteId);
//   }

//   Future<void> _flushChanges() async {
//     // if no note was created, we need to make it
//     if (_latestData == null) return;

//     //
//   }

//   Future<void> onTitleChanged(String text) async {
//     if (_latestData == null && text == '') {
//       // do nothing in this case
//       return;
//     }

//     await _ensureNoteIsCreated();

//     if (_latestData!.title.value != text) {
//       await notesRuntime.commands.updateNoteTitle.runThrowable(
//         UpdateNoteTitleInput(noteId: _latestData!.noteId, fullValue: text),
//       );
//       _latestData.copyWith
//       notifyListeners();
//     }
//   }

//   Future<void> submitContentEdit(dynamic textCqrdStuff) async {
//     //
//   }
// }
