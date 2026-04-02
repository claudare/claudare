import 'package:core/cqrs.dart';
import 'package:core/device_id.dart';
import 'package:notes_app_v0/command/create_note.dart';
import 'package:notes_app_v0/command/delete_note.dart';
import 'package:notes_app_v0/command/update_note_content.dart';
import 'package:notes_app_v0/command/update_note_title.dart';
import 'package:notes_app_v0/projection/note_projection.dart';
import 'package:notes_app_v0/repo/note/note_internal_repo.dart';
import 'package:notes_app_v0/repo/note/note_read_model.dart';

class NotesRuntime {
  final EventStore eventStore;

  // the read model is exposed directly
  final NoteReadModel noteReadModel;

  late final CqrsRuntime _cqrsRuntime;
  late final CqrsCommands commands;

  NotesRuntime({
    required this.eventStore,
    required CqrsRuntimeConfig cqrsConfig,
    required NoteInternalRepo noteInternalRepo,
    required this.noteReadModel,
  }) {
    // where does the deviceId come from?
    // does it come during the init phase or fetched automatically inside the CqrsRuntime?

    final noteProjection = NoteProjection(noteInternalRepo);

    _cqrsRuntime = CqrsRuntime(
      eventStore: eventStore,
      config: cqrsConfig,
      projectors: [noteProjection],
      thisDeviceId: DeviceId.unassigned(),
    );

    commands = CqrsCommands(
      createNote: _cqrsRuntime.bindCommand(CreateNote(), [noteProjection]),
      deleteNote: _cqrsRuntime.bindCommand(DeleteNote(), [noteProjection]),
      updateNoteContent: _cqrsRuntime.bindCommand(UpdateNoteContent(), [
        noteProjection,
      ]),
      updateNoteTitle: _cqrsRuntime.bindCommand(UpdateNoteTitle(), [
        noteProjection,
      ]),
    );
  }

  Future<void> init() async {
    await _cqrsRuntime.catchupAllProjections();
  }
}

class CqrsCommands {
  final BoundCommand<CreateNoteInput> createNote;
  final BoundCommand<DeleteNoteInput> deleteNote;
  final BoundCommand<UpdateNoteContentInput> updateNoteContent;
  final BoundCommand<UpdateNoteTitleInput> updateNoteTitle;

  const CqrsCommands({
    required this.createNote,
    required this.deleteNote,
    required this.updateNoteContent,
    required this.updateNoteTitle,
  });
}
